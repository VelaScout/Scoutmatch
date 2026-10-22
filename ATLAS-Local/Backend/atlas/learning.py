"""Lernen aus Erfahrung: Erfahrungsspeicher, Ergebnisbewertung, Reflexion, Korrekturen, Kennzahlen.

Was hier passiert – und was nicht:
- ATLAS wertet jede Aufgabe mit Werkzeugen aus (Ziel, Vorgehen, Werkzeuge, Erfolg, Fehler, Lehre) und
  speichert das durchsuchbar. Bei ähnlichen Aufgaben fließen bewährte Abläufe und Warnungen in den
  Kontext ein.
- Als „bewährt“ gilt nur, was Werkzeuge nachweislich bestätigt haben (verified) und was der Nutzer
  nicht korrigiert hat. Unbestätigtes bleibt „unbestätigt“ und wird nicht als gesichert verwendet.
- Korrekturen des Nutzers werden zu Regeln: dauerhaft („ab jetzt“, „immer“ …) gelten sie überall,
  sonst nur für ähnliche Aufgaben.
- Die Modellgewichte ändern sich dadurch NICHT. Das ist gespeichertes Wissen, kein Training.
"""
from __future__ import annotations

import json
import re
from collections import Counter
from collections.abc import Callable
from datetime import datetime, timedelta, timezone
from typing import Any

from .memory import jaccard, words

SCHEMA = [
    '''CREATE TABLE IF NOT EXISTS experiences (
        id INTEGER PRIMARY KEY, created_at TEXT NOT NULL, goal TEXT NOT NULL, task_type TEXT NOT NULL,
        mode TEXT, model TEXT, tools TEXT NOT NULL, outcome TEXT NOT NULL, verified INTEGER NOT NULL,
        errors TEXT NOT NULL, lesson TEXT NOT NULL, duration_s REAL, tool_calls INTEGER, tool_ok INTEGER,
        corrected INTEGER NOT NULL DEFAULT 0, feedback TEXT NOT NULL DEFAULT '')''',
    '''CREATE TABLE IF NOT EXISTS rules (
        id INTEGER PRIMARY KEY, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, text TEXT NOT NULL,
        kind TEXT NOT NULL, scope TEXT NOT NULL, task_type TEXT NOT NULL DEFAULT '', active INTEGER NOT NULL DEFAULT 1,
        source_experience INTEGER, uses INTEGER NOT NULL DEFAULT 0, edited INTEGER NOT NULL DEFAULT 0)''',
    '''CREATE TABLE IF NOT EXISTS metric_snapshots (day TEXT PRIMARY KEY, metrics TEXT NOT NULL)''',
]

TASK_TYPES = [
    ('code', {'run_tests', 'replace_in_file', 'inspect_project', 'run_command'}, r'code|projekt|fehler|bug|test|python|skript'),
    ('excel', {'create_spreadsheet'}, r'excel|tabelle|xlsx|csv'),
    ('pdf', {'create_pdf'}, r'pdf'),
    ('praesentation', {'create_presentation'}, r'powerpoint|präsentation|pptx'),
    ('sortieren', {'organize_folder', 'move_path'}, r'sortier|aufräum|ordne'),
    ('web', {'search_web', 'fetch_webpage', 'open_url', 'safari_current_page'}, r'such|recherch|internet|safari|web'),
    ('kalender', {'get_calendar_events', 'create_calendar_event'}, r'kalender|termin'),
    ('dateien', {'create_folder', 'write_file', 'read_file', 'list_directory', 'search_files', 'recent_files',
                 'delete_path'}, r'datei|ordner|speicher|notiz|dokument'),
    ('system', {'system_info', 'open_app', 'take_screenshot', 'analyze_screen'}, r'system|akku|speicherplatz|öffne|bildschirm'),
]
DURABLE = re.compile(r'\b(immer|ab jetzt|ab sofort|künftig|zukünftig|in zukunft|grundsätzlich|standardmäßig|jedes mal|'
                     r'nie wieder|nie mehr|bitte nie|generell|always|from now on|never)\b', re.I)
CORRECTION_PREFIX = re.compile(r'^\s*(atlas[,!.]?\s*)?((nein|falsch|stimmt nicht|nicht richtig|korrektur)[,.!:]*\s*|'
                               r'(das|es) (war|ist) (leider )?(nicht richtig|falsch|daneben)[,.!:]*\s*|'
                               r'du (liegst|hast) (leider )?(falsch|unrecht)[,.!:]*\s*)+', re.I)


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def task_type(goal: str, tools: list[str]) -> str:
    used = set(tools)
    for name, tool_names, pattern in TASK_TYPES:
        if used & tool_names:
            return name
    for name, _, pattern in TASK_TYPES:
        if re.search(pattern, goal.lower()):
            return name
    return 'sonstiges'


def error_class(output: str) -> str:
    """Grobe Fehlerart – damit wiederkehrende Fehler erkennbar werden."""
    text = output.lower()
    for key, pattern in [('pfad', r'außerhalb|gesperrt|nicht gefunden|existiert bereits'),
                         ('bestätigung', r'nicht bestätigt|abgelehnt'), ('argumente', r'fehlende angaben|ungültig|muss'),
                         ('zeitlimit', r'zeitlimit|timeout'), ('netz', r'offline|verbindung|nicht erreichbar'),
                         ('befehl', r'nicht erlaubt|exit-code'), ('werkzeug', r'unbekanntes werkzeug')]:
        if re.search(pattern, text):
            return key
    return 'sonstiges'


class Learning:
    def __init__(self, connect: Callable):
        """connect: Kontextmanager für die SQLite-Datenbank."""
        self.connect = connect
        with self.connect() as db:
            for statement in SCHEMA:
                db.execute(statement)

    # -- Ergebnisbewertung und Reflexion ------------------------------------------------------
    @staticmethod
    def evaluate(actions: list, finished: bool, cancelled: bool = False) -> tuple[str, bool]:
        """Ergebnis einer Aufgabe: ('erfolg'|'teilweise'|'fehlgeschlagen'|'abgebrochen'|'ohne_aktion', verifiziert)."""
        if cancelled:
            return 'abgebrochen', False
        if not actions:
            return 'ohne_aktion', False
        open_failures = []
        for i, action in enumerate(actions):
            if action.ok or action.declined:
                continue
            resolved = any(later.ok and later.tool == action.tool and later.summary == action.summary for later in actions[i + 1:])
            if not resolved:
                open_failures.append(action)
        successes = [a for a in actions if a.ok]
        if not successes:
            return 'fehlgeschlagen', False
        verified = all(a.verified for a in successes)
        if open_failures or any(a.declined for a in actions) or not finished:
            return 'teilweise', False
        return 'erfolg', verified

    @staticmethod
    def reflect(goal: str, actions: list, outcome: str, duration: float) -> str:
        """Was lässt sich für das nächste Mal lernen? (deterministisch, ohne Modell – nachvollziehbar)"""
        lessons = []
        for i, action in enumerate(actions):
            if action.ok or action.declined:
                continue
            fix = next((later for later in actions[i + 1:] if later.ok and later.tool != action.tool), None)
            same_fix = next((later for later in actions[i + 1:] if later.ok and later.tool == action.tool and later.summary == action.summary), None)
            if fix:
                lessons.append(f'Statt {action.tool} ({action.output[:80]}) hat {fix.tool} funktioniert.')
            elif same_fix:
                lessons.append(f'{action.tool} klappte erst im zweiten Anlauf; Fehler zuerst: {action.output[:80]}.')
            else:
                lessons.append(f'{action.tool} schlug fehl ({error_class(action.output)}): {action.output[:100]}.')
        declined = [a.tool for a in actions if a.declined]
        if declined:
            lessons.append('Vom Nutzer abgelehnt: ' + ', '.join(declined) + '.')
        if outcome == 'erfolg':
            steps = ' → '.join(dict.fromkeys(a.tool for a in actions if a.ok))
            lessons.insert(0, f'Bewährter Ablauf: {steps} ({duration:.0f} s).')
        elif outcome in ('fehlgeschlagen', 'teilweise') and not lessons:
            lessons.append('Aufgabe nicht vollständig erledigt; nächstes Mal zuerst die Eingaben prüfen.')
        return ' '.join(lessons)[:600]

    def record(self, goal: str, mode: str, model: str, actions: list, finished: bool, duration: float,
               cancelled: bool = False) -> int | None:
        """Speichert die Erfahrung einer Aufgabe mit Werkzeugen. Gibt die ID zurück (oder None)."""
        outcome, verified = self.evaluate(actions, finished, cancelled)
        if outcome == 'ohne_aktion':
            return None
        tools = [a.tool for a in actions]
        errors = [{'tool': a.tool, 'class': error_class(a.output), 'text': a.output[:200]}
                  for a in actions if not a.ok and not a.declined]
        lesson = self.reflect(goal, actions, outcome, duration)
        with self.connect() as db:
            cursor = db.execute(
                'INSERT INTO experiences(created_at, goal, task_type, mode, model, tools, outcome, verified, errors, '
                'lesson, duration_s, tool_calls, tool_ok) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
                (now(), goal[:1000], task_type(goal, tools), mode, model, json.dumps(tools), outcome, int(verified),
                 json.dumps(errors, ensure_ascii=False), lesson, round(duration, 2), len(actions),
                 sum(1 for a in actions if a.ok)))
            return cursor.lastrowid

    # -- Korrekturen -----------------------------------------------------------------------------
    def learn_correction(self, text: str, max_age_minutes: int = 60) -> dict | None:
        """Verknüpft eine Korrektur mit der letzten Aufgabe und speichert eine Regel."""
        instruction = CORRECTION_PREFIX.sub('', text).strip(' .!')
        if len(instruction) < 6:
            instruction = ''
        durable = bool(DURABLE.search(text))
        with self.connect() as db:
            row = db.execute('SELECT id, task_type, created_at, outcome FROM experiences ORDER BY id DESC LIMIT 1').fetchone()
            experience, kind_type = None, ''
            if row and datetime.fromisoformat(row[2]) > datetime.now(timezone.utc) - timedelta(minutes=max_age_minutes):
                experience, kind_type = row[0], row[1]
                db.execute("UPDATE experiences SET corrected=1, verified=0, feedback=?, "
                           "outcome=CASE WHEN outcome='erfolg' THEN 'korrigiert' ELSE outcome END WHERE id=?",
                           (text[:500], experience))
            if not instruction:
                return {'experience': experience, 'rule': None, 'scope': None}
            scope = 'dauerhaft' if durable else 'aehnliche_aufgaben'
            existing = db.execute('SELECT id, text FROM rules WHERE active=1').fetchall()
            for rule_id, rule_text in existing:
                if jaccard(rule_text, instruction) >= 0.8:
                    db.execute('UPDATE rules SET updated_at=?, text=?, scope=? WHERE id=?', (now(), instruction, scope, rule_id))
                    return {'experience': experience, 'rule': rule_id, 'scope': scope, 'updated': True}
            cursor = db.execute('INSERT INTO rules(created_at, updated_at, text, kind, scope, task_type, source_experience) '
                                'VALUES (?,?,?,?,?,?,?)', (now(), now(), instruction, 'korrektur', scope,
                                                           '' if durable else kind_type, experience))
            return {'experience': experience, 'rule': cursor.lastrowid, 'scope': scope}

    # -- Abruf für neue Aufgaben ----------------------------------------------------------------
    def context_for(self, goal: str, tools_hint: list[str] | None = None, limit: int = 3, rules_only: bool = False) -> str:
        """Textblock mit Regeln, bewährten Abläufen und Warnungen für eine neue Aufgabe."""
        kind = task_type(goal, tools_hint or [])
        with self.connect() as db:
            rules = db.execute('SELECT id, text, scope, task_type FROM rules WHERE active=1 ORDER BY id DESC LIMIT 100').fetchall()
            experiences = db.execute(
                'SELECT id, goal, task_type, outcome, verified, lesson, corrected FROM experiences '
                'ORDER BY id DESC LIMIT 300').fetchall()
        lines = []
        chosen_rules = [r for r in rules if r[2] == 'dauerhaft' or (r[3] and r[3] == kind) or jaccard(r[1], goal) >= 0.25]
        if chosen_rules:
            lines.append('Vom Nutzer gelernte Regeln (immer beachten):')
            lines += [f'- {r[1]}' for r in chosen_rules[:10]]
            with self.connect() as db:
                db.executemany('UPDATE rules SET uses=uses+1 WHERE id=?', [(r[0],) for r in chosen_rules[:10]])
        if rules_only:
            return '\n'.join(lines)
        scored = []
        for row in experiences:
            similarity = jaccard(row[1], goal) + (0.3 if row[2] == kind and kind != 'sonstiges' else 0)
            if similarity >= 0.3:
                scored.append((similarity, row))
        scored.sort(key=lambda item: item[0], reverse=True)
        proven = [r for _, r in scored if r[3] == 'erfolg' and r[4] and not r[6]][:limit]
        cautions = [r for _, r in scored if r[3] in ('fehlgeschlagen', 'teilweise', 'korrigiert')][:limit]
        if proven:
            lines.append('Bewährt bei ähnlichen Aufgaben (geprüft):')
            lines += [f'- „{r[1][:80]}“: {r[5][:200]}' for r in proven]
        if cautions:
            lines.append('Frühere Probleme bei ähnlichen Aufgaben (vermeiden):')
            lines += [f'- „{r[1][:80]}“: {r[5][:200]}' for r in cautions]
        return '\n'.join(lines)

    # -- Verwaltung (für die App) ----------------------------------------------------------------
    def list(self, table: str, limit: int = 100) -> list[dict]:
        if table not in ('experiences', 'rules'):
            raise ValueError('Unbekannte Liste.')
        with self.connect() as db:
            cursor = db.execute(f'SELECT * FROM {table} ORDER BY id DESC LIMIT ?', (limit,))
            names = [c[0] for c in cursor.description]
            return [dict(zip(names, row)) for row in cursor.fetchall()]

    def edit_rule(self, rule_id: int, text: str | None = None, active: bool | None = None, scope: str | None = None) -> bool:
        with self.connect() as db:
            if text is not None:
                if not text.strip() or len(text) > 500:
                    raise ValueError('Regeltext fehlt oder ist zu lang.')
                db.execute('UPDATE rules SET text=?, edited=1, updated_at=? WHERE id=?', (text.strip(), now(), rule_id))
            if active is not None:
                db.execute('UPDATE rules SET active=?, updated_at=? WHERE id=?', (int(active), now(), rule_id))
            if scope in ('dauerhaft', 'aehnliche_aufgaben'):
                db.execute('UPDATE rules SET scope=?, updated_at=? WHERE id=?', (scope, now(), rule_id))
            return db.execute('SELECT changes()').fetchone()[0] > 0

    def delete(self, table: str, item_id: int) -> bool:
        if table not in ('experiences', 'rules'):
            raise ValueError('Unbekannte Liste.')
        with self.connect() as db:
            db.execute(f'DELETE FROM {table} WHERE id=?', (item_id,))
            return db.execute('SELECT changes()').fetchone()[0] > 0

    def confirm_experience(self, item_id: int, good: bool) -> None:
        """Nutzer bestätigt oder verwirft eine Erfahrung (z. B. in der App)."""
        with self.connect() as db:
            if good:
                db.execute("UPDATE experiences SET verified=1, corrected=0 WHERE id=?", (item_id,))
            else:
                db.execute("UPDATE experiences SET verified=0, corrected=1, "
                           "outcome=CASE WHEN outcome='erfolg' THEN 'korrigiert' ELSE outcome END WHERE id=?", (item_id,))

    # -- Kennzahlen -------------------------------------------------------------------------------
    def metrics(self, days: int = 30) -> dict[str, Any]:
        since = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()
        with self.connect() as db:
            rows = db.execute('SELECT mode, outcome, duration_s, tool_calls, tool_ok, errors, corrected FROM experiences '
                              'WHERE created_at >= ?', (since,)).fetchall()
            rules = db.execute('SELECT count(*), sum(edited), sum(1-active) FROM rules').fetchone()
        complex_rows = [r for r in rows if r[0] in ('agent', 'plan')]
        successes = sum(1 for r in complex_rows if r[1] == 'erfolg')
        calls = sum(r[3] or 0 for r in rows)
        ok = sum(r[4] or 0 for r in rows)
        signatures = Counter()
        for row in rows:
            for error in json.loads(row[5] or '[]'):
                signatures[(error['tool'], error['class'])] += 1
        repeated = sum(count for count in signatures.values() if count >= 2)
        total_rules = rules[0] or 0
        return {
            'tasks': len(rows),
            'success_rate': round(successes / len(complex_rows), 3) if complex_rows else None,
            'tool_reliability': round(ok / calls, 3) if calls else None,
            'avg_duration_s': round(sum(r[2] or 0 for r in rows) / len(rows), 1) if rows else None,
            'repeated_errors': repeated,
            'corrections': sum(r[6] for r in rows),
            'rules': total_rules,
            'memory_correctness': round(1 - ((rules[1] or 0) + (rules[2] or 0)) / total_rules, 3) if total_rules else None,
            'top_errors': [{'tool': t, 'class': c, 'count': n} for (t, c), n in signatures.most_common(5)],
        }

    def snapshot(self, extra: dict | None = None) -> dict:
        """Tageswert speichern – daraus entsteht der Verlauf in der App."""
        values = {**self.metrics(), **(extra or {})}
        day = datetime.now(timezone.utc).date().isoformat()
        with self.connect() as db:
            db.execute('INSERT OR REPLACE INTO metric_snapshots(day, metrics) VALUES (?,?)', (day, json.dumps(values)))
        return values

    def history(self, days: int = 60) -> list[dict]:
        with self.connect() as db:
            rows = db.execute('SELECT day, metrics FROM metric_snapshots ORDER BY day DESC LIMIT ?', (days,)).fetchall()
        return [{'day': day, **json.loads(values)} for day, values in reversed(rows)]

    def export_training_data(self) -> list[dict]:
        """Bestätigte Beispiele als Chat-Datensatz (JSONL-fähig) – Grundlage für ein späteres, freigegebenes
        Fine-Tuning. Es wird hier NICHT trainiert."""
        with self.connect() as db:
            rows = db.execute("SELECT goal, lesson FROM experiences WHERE outcome='erfolg' AND verified=1 AND corrected=0").fetchall()
            rules = db.execute("SELECT text FROM rules WHERE active=1").fetchall()
        data = [{'messages': [{'role': 'user', 'content': goal}, {'role': 'assistant', 'content': lesson}]} for goal, lesson in rows]
        data += [{'messages': [{'role': 'system', 'content': 'Regel des Nutzers'}, {'role': 'user', 'content': text}]} for (text,) in rules]
        return data
