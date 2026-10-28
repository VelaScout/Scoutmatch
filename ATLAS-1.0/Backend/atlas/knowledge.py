"""Wissensaufbau: ATLAS lernt ein Thema aus Quellen – mit Quelle, Datum und Status je Aussage.

Ablauf (learn):
1. Websuche nach dem Thema, die besten Quellen werden gelesen.
2. Das lokale Modell zieht Aussagen NUR aus dem jeweiligen Quelltext heraus.
3. Belegprüfung ohne Modell: Eine Aussage wird nur gespeichert, wenn ihre Kernwörter wirklich im
   Quelltext stehen. Was das Modell „dazuerfindet“, fällt hier heraus.
4. Abgleich zwischen Quellen: ähnliche Aussagen aus mehreren Quellen → „mehrfach belegt“;
   vom Modell gemeldete Widersprüche → „widerspruch“ (beide Seiten bleiben sichtbar).
5. Offene Fragen und dünne Stellen werden als Wissenslücken festgehalten.

Status je Aussage: belegt | mehrfach_belegt | vermutung (Quelle selbst schätzt/meint) | widerspruch.
Wissen aus der Wissensbasis wird im Gespräch immer mit Quelle genannt und bleibt so von
Vermutungen des Modells unterscheidbar.
"""
from __future__ import annotations

import json
import re
import sqlite3
from collections.abc import Callable
from datetime import datetime, timezone

from .learning import now
from .llm import ModelError
from .memory import jaccard, words

SCHEMA = [
    '''CREATE TABLE IF NOT EXISTS knowledge_topics (
        id INTEGER PRIMARY KEY, topic TEXT NOT NULL, status TEXT NOT NULL, created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL, sources INTEGER NOT NULL DEFAULT 0, gaps TEXT NOT NULL DEFAULT '[]',
        note TEXT NOT NULL DEFAULT '')''',
    '''CREATE TABLE IF NOT EXISTS knowledge_fact_sources (
        fact_id INTEGER NOT NULL, source_url TEXT NOT NULL,
        PRIMARY KEY (fact_id, source_url))''',
    '''CREATE TABLE IF NOT EXISTS knowledge_facts (
        id INTEGER PRIMARY KEY, topic_id INTEGER NOT NULL, statement TEXT NOT NULL, kind TEXT NOT NULL,
        status TEXT NOT NULL, source_url TEXT NOT NULL, source_title TEXT NOT NULL, retrieved_at TEXT NOT NULL,
        support INTEGER NOT NULL DEFAULT 1, conflict_with INTEGER, edited INTEGER NOT NULL DEFAULT 0)''',
]
KINDS = ('definition', 'methode', 'fakt', 'zahl', 'meinung')
EXTRACT = """Lies den Quelltext und ziehe die wichtigsten Aussagen zum Thema „{topic}“ heraus.
Regeln:
- NUR was im Text steht. Nichts aus eigenem Wissen ergänzen. Keine Aussage ohne Grundlage im Text.
- Jede Aussage kurz (ein Satz, Deutsch), möglichst mit den Worten des Textes.
- kind: definition | methode | fakt | zahl | meinung (meinung = Schätzung, Prognose oder Ansicht des Autors).
- open_questions: was zum Thema wichtig wäre, aber im Text fehlt.
Antworte nur mit JSON: {{"facts": [{{"statement": "...", "kind": "..."}}], "open_questions": ["..."]}}

Quelltext ({title}):
{text}"""
CONFLICTS = """Hier sind Aussagen zum Thema „{topic}“ aus verschiedenen Quellen (Nummer: Aussage).
Welche Paare widersprechen sich inhaltlich direkt? Nur echte Widersprüche, keine Ergänzungen.
Antworte nur mit JSON: {{"conflicts": [[nummer, nummer]]}}

{facts}"""
MIN_GROUNDING = 0.6


def grounded(statement: str, source: str) -> float:
    """Anteil der Kernwörter einer Aussage, die im Quelltext vorkommen (0–1)."""
    core = {w for w in words(statement) if len(w) > 3}
    if not core:
        return 0.0
    text = source.lower()
    return sum(1 for w in core if w[:6] in text) / len(core)


class Knowledge:
    def __init__(self, connect: Callable, llm=None, search: Callable[[str], list[dict]] | None = None,
                 fetch: Callable[[str], str] | None = None, log=None):
        self.connect = connect
        self.llm = llm
        self.search = search
        self.fetch = fetch
        self.log = log or (lambda *_: None)
        self.fts = False
        with self.connect() as db:
            for statement in SCHEMA:
                db.execute(statement)
            # Preserve original provenance and migrate existing facts idempotently.
            db.execute("""INSERT OR IGNORE INTO knowledge_fact_sources(fact_id,source_url)
                SELECT id,source_url FROM knowledge_facts WHERE trim(source_url) != ''""")
            # SQLite FTS5: use disk-backed full-text search instead of scanning every fact.
            # Existing installations are indexed on upgrade without modifying fact records.
            try:
                db.execute("CREATE VIRTUAL TABLE IF NOT EXISTS knowledge_search USING fts5(statement, topic, content='')")
                db.execute("""CREATE TRIGGER IF NOT EXISTS knowledge_facts_ai AFTER INSERT ON knowledge_facts BEGIN
                    INSERT INTO knowledge_search(rowid,statement,topic) VALUES(new.id,new.statement,
                        (SELECT topic FROM knowledge_topics WHERE id=new.topic_id)); END""")
                db.execute("""CREATE TRIGGER IF NOT EXISTS knowledge_facts_ad AFTER DELETE ON knowledge_facts BEGIN
                    INSERT INTO knowledge_search(knowledge_search,rowid,statement,topic)
                    VALUES('delete',old.id,old.statement,(SELECT topic FROM knowledge_topics WHERE id=old.topic_id)); END""")
                db.execute("""CREATE TRIGGER IF NOT EXISTS knowledge_facts_au AFTER UPDATE OF statement ON knowledge_facts BEGIN
                    INSERT INTO knowledge_search(knowledge_search,rowid,statement,topic)
                    VALUES('delete',old.id,old.statement,(SELECT topic FROM knowledge_topics WHERE id=old.topic_id));
                    INSERT INTO knowledge_search(rowid,statement,topic) VALUES(new.id,new.statement,
                        (SELECT topic FROM knowledge_topics WHERE id=new.topic_id)); END""")
                count = db.execute('SELECT count(*) FROM knowledge_facts').fetchone()[0]
                indexed = db.execute('SELECT count(*) FROM knowledge_search').fetchone()[0]
                if count != indexed:
                    db.execute("INSERT INTO knowledge_search(knowledge_search) VALUES('delete-all')")
                    db.execute("""INSERT INTO knowledge_search(rowid,statement,topic)
                        SELECT f.id,f.statement,t.topic FROM knowledge_facts f
                        JOIN knowledge_topics t ON t.id=f.topic_id""")
                self.fts = True
            except Exception:  # SQLite builds without FTS5 still work via the older scan.
                self.log('FTS5 nicht verfügbar; nutze die langsamere Standardsuche.')

    # -- Lernen ------------------------------------------------------------------------------------
    def learn(self, topic: str, model: str, max_sources: int = 4, stop=None) -> dict:
        topic = topic.strip()[:200]
        if not topic:
            raise ValueError('Thema fehlt.')
        if not (self.llm and self.search and self.fetch):
            raise ValueError('Wissensaufbau braucht Modell, Suche und Internet.')
        with self.connect() as db:
            row = db.execute('SELECT id FROM knowledge_topics WHERE lower(topic)=lower(?)', (topic,)).fetchone()
            if row:
                topic_id = row[0]
                db.execute("UPDATE knowledge_topics SET status='in_arbeit', updated_at=? WHERE id=?", (now(), topic_id))
            else:
                topic_id = db.execute("INSERT INTO knowledge_topics(topic, status, created_at, updated_at) VALUES (?,?,?,?)",
                                      (topic, 'in_arbeit', now(), now())).lastrowid
        try:
            results = self.search(topic) or []
        except Exception as exc:  # noqa: BLE001 – Netzfehler ehrlich festhalten
            return self._finish(topic_id, 'fehlgeschlagen', [], 0, f'Suche nicht möglich: {exc}')
        seen, sources, gaps, stored, rejected = set(), 0, [], 0, 0
        for result in results:
            if stop is not None and stop.is_set():
                return self._finish(topic_id, 'abgebrochen', gaps, sources, 'Abgebrochen.')
            url = result.get('url', '')
            if not url.startswith(('http://', 'https://')) or url in seen:
                continue
            seen.add(url)
            try:
                text = self.fetch(url)
            except Exception as exc:  # noqa: BLE001
                self.log(f'Quelle nicht lesbar: {url}: {exc}')
                continue
            if len(text) < 300:
                continue
            text = text[:7000]
            try:
                reply = self.llm.chat(model, [{'role': 'user', 'content': EXTRACT.format(
                    topic=topic, title=result.get('title', url)[:120], text=text)}],
                    json_mode=True, num_predict=1500, num_ctx=8192, timeout=300)
                data = json.loads(reply.content or '{}')
            except (ModelError, ValueError):
                continue
            sources += 1
            gaps += [str(q).strip()[:200] for q in data.get('open_questions') or [] if str(q).strip()]
            for fact in data.get('facts') or []:
                statement = str(fact.get('statement', '')).strip()[:400] if isinstance(fact, dict) else ''
                if len(statement) < 12:
                    continue
                if grounded(statement, text) < MIN_GROUNDING:
                    rejected += 1          # nicht im Quelltext belegt → wird nicht als Wissen gespeichert
                    continue
                kind = fact.get('kind') if fact.get('kind') in KINDS else 'fakt'
                stored += self._store(topic_id, statement, kind, url, result.get('title', '')[:200])
            if sources >= max_sources:
                break
        if not sources:
            return self._finish(topic_id, 'fehlgeschlagen', gaps, 0, 'Keine lesbaren Quellen gefunden.')
        self._find_conflicts(topic_id, topic, model)
        if stored < 3:
            gaps.append('Zu wenige belegte Aussagen – weitere Quellen nötig.')
        note = f'{stored} belegte Aussagen aus {sources} Quellen; {rejected} unbelegte Aussagen verworfen.'
        return self._finish(topic_id, 'gelernt', gaps, sources, note, stored=stored, rejected=rejected)

    def _store(self, topic_id: int, statement: str, kind: str, url: str, title: str) -> int:
        status = 'vermutung' if kind == 'meinung' else 'belegt'
        with self.connect() as db:
            rows = db.execute('SELECT id, statement, source_url FROM knowledge_facts WHERE topic_id=?', (topic_id,)).fetchall()
            for fact_id, existing, existing_url in rows:
                if jaccard(existing, statement) >= 0.5:
                    if url and existing_url != url:
                        added = db.execute('INSERT OR IGNORE INTO knowledge_fact_sources(fact_id,source_url) VALUES (?,?)',
                                           (fact_id, url)).rowcount
                        if added:
                            db.execute("UPDATE knowledge_facts SET support=support+1, status=CASE WHEN status='belegt' "
                                       "THEN 'mehrfach_belegt' ELSE status END WHERE id=?", (fact_id,))
                    return 0
            db.execute('INSERT INTO knowledge_facts(topic_id, statement, kind, status, source_url, source_title, retrieved_at) '
                       'VALUES (?,?,?,?,?,?,?)', (topic_id, statement, kind, status, url, title,
                                                  datetime.now(timezone.utc).date().isoformat()))
            if url:
                fact_id = db.execute('SELECT last_insert_rowid()').fetchone()[0]
                db.execute('INSERT OR IGNORE INTO knowledge_fact_sources(fact_id,source_url) VALUES (?,?)', (fact_id, url))
        return 1

    def _find_conflicts(self, topic_id: int, topic: str, model: str) -> None:
        with self.connect() as db:
            facts = db.execute('SELECT id, statement, source_url FROM knowledge_facts WHERE topic_id=? ORDER BY id LIMIT 40',
                               (topic_id,)).fetchall()
        if len({f[2] for f in facts}) < 2:
            return
        listing = '\n'.join(f'{i}: {f[1]}' for i, f in enumerate(facts, 1))
        try:
            reply = self.llm.chat(model, [{'role': 'user', 'content': CONFLICTS.format(topic=topic, facts=listing)}],
                                  json_mode=True, num_predict=300, timeout=180)
            pairs = json.loads(reply.content or '{}').get('conflicts') or []
        except (ModelError, ValueError, AttributeError):
            return
        with self.connect() as db:
            for pair in pairs:
                if not (isinstance(pair, list) and len(pair) == 2 and all(isinstance(n, int) and 1 <= n <= len(facts) for n in pair)):
                    continue
                first, second = facts[pair[0] - 1], facts[pair[1] - 1]
                if first[0] == second[0] or first[2] == second[2]:
                    continue          # Widerspruch nur zwischen verschiedenen Quellen
                db.execute("UPDATE knowledge_facts SET status='widerspruch', conflict_with=? WHERE id=?", (second[0], first[0]))
                db.execute("UPDATE knowledge_facts SET status='widerspruch', conflict_with=? WHERE id=?", (first[0], second[0]))

    def _finish(self, topic_id: int, status: str, gaps: list[str], sources: int, note: str, **extra) -> dict:
        unique = list(dict.fromkeys(gaps))[:15]
        with self.connect() as db:
            db.execute('UPDATE knowledge_topics SET status=?, gaps=?, sources=?, note=?, updated_at=? WHERE id=?',
                       (status, json.dumps(unique, ensure_ascii=False), sources, note, now(), topic_id))
        return {'status': status, 'topic_id': topic_id, 'sources': sources, 'gaps': unique, 'note': note, **extra}

    # -- Nutzen ------------------------------------------------------------------------------------
    def context_for(self, question: str, limit: int = 6) -> str:
        """Passende Aussagen mit Quelle – für Antworten, die Wissen und Vermutung trennen."""
        with self.connect() as db:
            rows = []
            if self.fts:
                # Quote individual terms; never allow user input to become FTS query syntax.
                tokens = list(dict.fromkeys(t for t in words(question) if len(t) >= 4))[:12]
                if tokens:
                    query = ' OR '.join('"' + t.replace('"', '""') + '"' for t in tokens)
                    try:
                        rows = db.execute("""SELECT f.statement,f.status,f.source_title,f.source_url,
                            f.retrieved_at,t.topic FROM knowledge_search s
                            JOIN knowledge_facts f ON f.id=s.rowid
                            JOIN knowledge_topics t ON t.id=f.topic_id
                            WHERE knowledge_search MATCH ? ORDER BY bm25(knowledge_search) LIMIT 250""",
                            (query,)).fetchall()
                    except sqlite3.OperationalError:
                        rows = []
            if not rows:
                # Bounded SQL candidate search avoids loading the entire knowledge base
                # into Python when FTS cannot match inflected or compound words.
                terms = list(dict.fromkeys(w[:6] for w in words(question) if len(w) >= 4))[:8]
                if terms:
                    predicates = ' OR '.join(['lower(f.statement) LIKE ? OR lower(t.topic) LIKE ?'] * len(terms))
                    params = [pattern for term in terms for pattern in (f'%{term}%', f'%{term}%')]
                    rows = db.execute('SELECT f.statement,f.status,f.source_title,f.source_url,f.retrieved_at,t.topic '
                                      'FROM knowledge_facts f JOIN knowledge_topics t ON t.id=f.topic_id '
                                      f'WHERE {predicates} ORDER BY f.id DESC LIMIT 250', params).fetchall()
        asked = set(words(question))
        scored = []
        for row in rows:
            topic_hit = bool(asked & set(words(row[5])))
            score = jaccard(row[0], question) + (0.25 if topic_hit else 0)
            if score >= 0.2:
                scored.append((score, row))
        if not scored:
            return ''
        scored.sort(key=lambda item: item[0], reverse=True)
        lines = ['Aus deiner Wissensbasis (mit Quellen; „vermutung“/„widerspruch“ ausdrücklich so benennen, '
                 'eigenes Modellwissen als Einschätzung kennzeichnen):']
        for _, (statement, status, title, url, day, _) in scored[:limit]:
            lines.append(f'- [{status}] {statement} (Quelle: {title or url}, {url}, abgerufen {day})')
        return '\n'.join(lines)

    def audit(self, stale_days: int = 365) -> dict:
        """Diagnose der Wissensbasis ohne Internet und ohne Änderung der gespeicherten Fakten."""
        from datetime import timedelta
        if not 1 <= stale_days <= 3650:
            raise ValueError('stale_days muss zwischen 1 und 3650 liegen.')
        cutoff = (datetime.now(timezone.utc) - timedelta(days=stale_days)).date().isoformat()
        with self.connect() as db:
            topics = db.execute('SELECT count(*) FROM knowledge_topics').fetchone()[0]
            facts = db.execute('SELECT count(*) FROM knowledge_facts').fetchone()[0]
            unsourced = db.execute("SELECT count(*) FROM knowledge_facts WHERE trim(source_url)='' OR source_url NOT LIKE 'http%'").fetchone()[0]
            stale = db.execute('SELECT count(*) FROM knowledge_facts WHERE retrieved_at < ?', (cutoff,)).fetchone()[0]
            conflicts = db.execute("SELECT count(*) FROM knowledge_facts WHERE status='widerspruch'").fetchone()[0]
            thin = db.execute("""SELECT count(*) FROM knowledge_topics t
                WHERE (SELECT count(*) FROM knowledge_facts f WHERE f.topic_id=t.id)<3""").fetchone()[0]
        return {'topics':topics,'facts':facts,'without_url':unsourced,'stale':stale,
                'conflicts':conflicts,'thin_topics':thin,'fulltext_enabled':self.fts,
                'stale_days':stale_days}

    # -- Verwaltung (für die App) ------------------------------------------------------------------
    def topics(self) -> list[dict]:
        with self.connect() as db:
            cursor = db.execute('SELECT t.*, (SELECT count(*) FROM knowledge_facts f WHERE f.topic_id=t.id) AS facts '
                                'FROM knowledge_topics t ORDER BY t.updated_at DESC LIMIT 100')
            names = [c[0] for c in cursor.description]
            items = [dict(zip(names, row)) for row in cursor.fetchall()]
        for item in items:
            item['gaps'] = json.loads(item['gaps'] or '[]')
        return items

    def facts(self, topic_id: int) -> list[dict]:
        with self.connect() as db:
            cursor = db.execute('SELECT * FROM knowledge_facts WHERE topic_id=? ORDER BY status, id', (topic_id,))
            names = [c[0] for c in cursor.description]
            return [dict(zip(names, row)) for row in cursor.fetchall()]

    def edit_fact(self, fact_id: int, statement: str | None = None, status: str | None = None) -> bool:
        with self.connect() as db:
            if statement is not None:
                if not statement.strip() or len(statement) > 400:
                    raise ValueError('Aussage fehlt oder ist zu lang.')
                db.execute('UPDATE knowledge_facts SET statement=?, edited=1 WHERE id=?', (statement.strip(), fact_id))
            if status in ('belegt', 'mehrfach_belegt', 'vermutung', 'widerspruch'):
                db.execute('UPDATE knowledge_facts SET status=?, edited=1 WHERE id=?', (status, fact_id))
            return db.execute('SELECT changes()').fetchone()[0] > 0

    def delete(self, kind: str, item_id: int) -> bool:
        with self.connect() as db:
            if kind == 'fact':
                db.execute('DELETE FROM knowledge_fact_sources WHERE fact_id=?', (item_id,))
                db.execute('DELETE FROM knowledge_facts WHERE id=?', (item_id,))
            elif kind == 'topic':
                db.execute('DELETE FROM knowledge_fact_sources WHERE fact_id IN (SELECT id FROM knowledge_facts WHERE topic_id=?)', (item_id,))
                db.execute('DELETE FROM knowledge_facts WHERE topic_id=?', (item_id,))
                db.execute('DELETE FROM knowledge_topics WHERE id=?', (item_id,))
            else:
                raise ValueError('Unbekannte Art.')
            return db.execute('SELECT changes()').fetchone()[0] > 0

