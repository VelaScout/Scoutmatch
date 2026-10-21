"""Verbesserungsmotor: wiederkehrende Probleme erkennen, bessere Arbeitsweisen vorschlagen, prüfen, zurücknehmen.

Ablauf:
1. analyze(): wertet die Kennzahlen aus (wiederholte Fehler, langsame Aufgabenarten, unzuverlässige
   Werkzeuge) und priorisiert nach Häufigkeit.
2. Für jedes Problem entsteht ein Hinweis (eine Arbeitsanweisung für den Agenten). Ist ein Bewerter
   angeschlossen (z. B. die Echttest-Fälle auf dem Mac), wird mit und ohne Hinweis gemessen; nur ein
   Hinweis, der nicht schlechter abschneidet, wird vorgeschlagen.
3. Aktiv wird ein Hinweis erst nach Freigabe – als Regel „verbesserung“ im Erfahrungsspeicher.
4. review(): Tritt der Fehler trotz aktivem Hinweis genauso oft wieder auf, wird der Hinweis
   automatisch zurückgenommen (Status „zurueckgesetzt“). Das ist sicher: ein Hinweis ist nur Text.
Keine Sicherheitsregel wird hier je verändert.
"""
from __future__ import annotations

import json
from collections.abc import Callable
from datetime import datetime, timedelta, timezone

from .approvals import Approvals
from .learning import Learning, now

SCHEMA = '''CREATE TABLE IF NOT EXISTS improvement_hints (
    id INTEGER PRIMARY KEY, proposal_id INTEGER NOT NULL, signature TEXT NOT NULL, text TEXT NOT NULL,
    rule_id INTEGER, status TEXT NOT NULL, baseline INTEGER NOT NULL, activated_at TEXT, result TEXT NOT NULL DEFAULT '')'''

ERROR_HINTS = {
    'pfad': 'Bei {tool}: Pfad zuerst mit list_directory oder search_files prüfen; Ordner wie „~/Documents“ verwenden; '
            'existiert eine Datei schon, einen neuen Namen wählen statt zu überschreiben.',
    'argumente': 'Bei {tool}: alle Pflichtangaben vollständig und im richtigen Format übergeben, nicht raten.',
    'zeitlimit': 'Bei {tool}: Aufgabe in kleinere Schritte teilen und weniger Daten auf einmal verarbeiten.',
    'netz': 'Bei {tool}: Ist das Internet nicht erreichbar, das ehrlich sagen und keine Ergebnisse erfinden.',
    'befehl': 'Bei {tool}: nur erlaubte Befehle verwenden; für Tests run_tests, für Projekte inspect_project nutzen.',
    'bestätigung': 'Bei {tool}: Hat der Nutzer abgelehnt, nicht erneut versuchen, sondern nachfragen, was er stattdessen möchte.',
    'werkzeug': 'Nur Werkzeuge aus der angebotenen Liste aufrufen; {tool} gibt es nicht.',
    'sonstiges': 'Bei {tool}: Fehlermeldung lesen und das Vorgehen ändern, statt denselben Aufruf zu wiederholen.',
}
SLOW_SECONDS = 60


class Improvement:
    def __init__(self, connect: Callable, learning: Learning, approvals: Approvals,
                 evaluate: Callable[[str | None], float] | None = None):
        """evaluate(hint or None) → Erfolgsquote 0–1 auf festen Testfällen (optional)."""
        self.connect = connect
        self.learning = learning
        self.approvals = approvals
        self.evaluate = evaluate
        with self.connect() as db:
            db.execute(SCHEMA)
        approvals.register('hint', self._activate)

    # -- Analyse -----------------------------------------------------------------------------------
    def problems(self, days: int = 30) -> list[dict]:
        """Priorisierte Liste erkannter Probleme (häufigste zuerst)."""
        metrics = self.learning.metrics(days)
        found = [{'signature': f"{e['tool']}:{e['class']}", 'count': e['count'], 'kind': 'fehler',
                  'text': ERROR_HINTS.get(e['class'], ERROR_HINTS['sonstiges']).format(tool=e['tool'])}
                 for e in metrics['top_errors'] if e['count'] >= 2]
        since = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()
        with self.connect() as db:
            slow = db.execute('SELECT task_type, count(*), avg(duration_s) FROM experiences WHERE created_at>=? '
                              "AND mode IN ('agent','plan') GROUP BY task_type HAVING count(*)>=3 AND avg(duration_s)>?",
                              (since, SLOW_SECONDS)).fetchall()
        found += [{'signature': f'langsam:{kind}', 'count': count, 'kind': 'langsam',
                   'text': f'Bei Aufgaben der Art „{kind}“: direkt das passende Werkzeug aufrufen, ohne lange Vorüberlegung, '
                           'und mehrere Schritte möglichst mit einem Werkzeug erledigen.'}
                  for kind, count, _ in slow]
        return sorted(found, key=lambda p: p['count'], reverse=True)

    def analyze(self, days: int = 30) -> list[int]:
        """Erzeugt Vorschläge für neue Probleme. Gibt die Vorschlags-IDs zurück."""
        proposals = []
        self._sync()
        with self.connect() as db:      # abgelehnte oder zurückgenommene Hinweise werden nicht erneut vorgeschlagen
            known = {row[0] for row in db.execute('SELECT signature FROM improvement_hints').fetchall()}
        for problem in self.problems(days):
            if problem['signature'] in known:
                continue
            evaluation = None
            if self.evaluate:
                before, after = self.evaluate(None), self.evaluate(problem['text'])
                evaluation = {'ohne': round(before, 3), 'mit': round(after, 3)}
                if after < before:
                    continue          # Hinweis verschlechtert die Testfälle → wird nicht vorgeschlagen
            title = ('Ich habe eine bessere Methode gefunden: ' if problem['kind'] == 'fehler' else 'Schneller arbeiten: ') \
                + problem['signature']
            proposal = self.approvals.propose('hint', title, {
                'signature': problem['signature'], 'text': problem['text'], 'count': problem['count'],
                'evaluation': evaluation})
            with self.connect() as db:
                db.execute('INSERT INTO improvement_hints(proposal_id, signature, text, status, baseline) VALUES (?,?,?,?,?)',
                           (proposal, problem['signature'], problem['text'], 'wartet', problem['count']))
            proposals.append(proposal)
        return proposals

    # -- Aktivieren und überprüfen -------------------------------------------------------------------
    def _activate(self, detail: dict) -> str:
        with self.connect() as db:
            row = db.execute("SELECT id FROM improvement_hints WHERE signature=? AND status='wartet' ORDER BY id DESC",
                             (detail['signature'],)).fetchone()
            rule = db.execute("INSERT INTO rules(created_at, updated_at, text, kind, scope) VALUES (?,?,?,?,?)",
                              (now(), now(), detail['text'], 'verbesserung', 'dauerhaft')).lastrowid
            if row:
                db.execute("UPDATE improvement_hints SET status='aktiv', rule_id=?, activated_at=? WHERE id=?",
                           (rule, now(), row[0]))
        return f'Arbeitsanweisung aktiv (Regel {rule}).'

    def review(self, min_days: float = 3) -> list[str]:
        """Nimmt Hinweise zurück, die nicht geholfen haben (Fehler seit Aktivierung nicht seltener)."""
        undone = []
        with self.connect() as db:
            active = db.execute("SELECT id, proposal_id, signature, rule_id, baseline, activated_at FROM improvement_hints "
                                "WHERE status='aktiv'").fetchall()
        for hint_id, proposal, signature, rule_id, baseline, activated in active:
            if signature.startswith('langsam:'):
                continue
            since = datetime.fromisoformat(activated)
            if datetime.now(timezone.utc) - since < timedelta(days=min_days):
                continue
            tool, error = signature.split(':', 1)
            with self.connect() as db:
                rows = db.execute('SELECT errors FROM experiences WHERE created_at>=?', (activated,)).fetchall()
            after = sum(1 for (errors,) in rows for e in json.loads(errors or '[]')
                        if e['tool'] == tool and e['class'] == error)
            if after >= baseline:
                self.rollback(hint_id, f'Fehler trat danach weiter auf ({after}×) – automatisch zurückgenommen.')
                undone.append(signature)
            else:
                with self.connect() as db:
                    db.execute('UPDATE improvement_hints SET result=? WHERE id=?', (f'Fehler danach {after}× statt {baseline}×.', hint_id))
        return undone

    def rollback(self, hint_id: int, reason: str = 'Vom Nutzer zurückgenommen.') -> None:
        with self.connect() as db:
            row = db.execute('SELECT proposal_id, rule_id FROM improvement_hints WHERE id=?', (hint_id,)).fetchone()
            if not row:
                raise ValueError('Hinweis nicht gefunden.')
            if row[1]:
                db.execute('UPDATE rules SET active=0, updated_at=? WHERE id=?', (now(), row[1]))
            db.execute("UPDATE improvement_hints SET status='zurueckgesetzt', result=? WHERE id=?", (reason, hint_id))
        self.approvals.mark(row[0], 'zurueckgesetzt', reason)

    def _sync(self) -> None:
        """Abgelehnte oder fehlgeschlagene Freigaben in die Hinweisliste übernehmen."""
        with self.connect() as db:
            db.execute("UPDATE improvement_hints SET status=(SELECT p.status FROM proposals p WHERE p.id=proposal_id) "
                       "WHERE status='wartet' AND (SELECT p.status FROM proposals p WHERE p.id=proposal_id) "
                       "IN ('abgelehnt','fehlgeschlagen')")

    def list(self) -> list[dict]:
        self._sync()
        with self.connect() as db:
            cursor = db.execute('SELECT * FROM improvement_hints ORDER BY id DESC LIMIT 100')
            names = [c[0] for c in cursor.description]
            return [dict(zip(names, row)) for row in cursor.fetchall()]
