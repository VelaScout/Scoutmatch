"""Aufgabenjournal: Folgeaufträge, Wiederaufnahme und Schutz vor doppelten Aktionen.

- Jede Aufgabe mit Werkzeugen wird festgehalten: Ziel, Schritte (erledigt / fehlgeschlagen / abgelehnt),
  offene Schritte, erzeugte Dateien, Status. Das überlebt Neustarts (SQLite).
- Folgeaufträge („Mach weiter“, „Ändere das“, „Speichere es als PDF“) bekommen genau diesen Zusammenhang:
  welche Datei gemeint ist und was schon erledigt ist – damit nichts doppelt gemacht wird.
- Aktionen mit Außenwirkung (E-Mail, Nachricht, Anruf, Termin, Erinnerung, Kurzbefehl) werden mit
  ihrem Inhalt protokolliert. Dieselbe Aktion innerhalb von 24 Stunden wird nicht still wiederholt:
  ATLAS fragt ausdrücklich nach, sonst bleibt es bei der ersten Ausführung.
"""
from __future__ import annotations

import hashlib
import json
import re
from collections.abc import Callable
from datetime import datetime, timedelta, timezone

SCHEMA = [
    '''CREATE TABLE IF NOT EXISTS tasks (
        id INTEGER PRIMARY KEY, created_at TEXT NOT NULL, goal TEXT NOT NULL, mode TEXT NOT NULL, status TEXT NOT NULL,
        steps TEXT NOT NULL, open_steps TEXT NOT NULL, artifacts TEXT NOT NULL, reason TEXT NOT NULL DEFAULT '',
        resumed_from INTEGER)''',
    '''CREATE TABLE IF NOT EXISTS side_effects (
        id INTEGER PRIMARY KEY, created_at TEXT NOT NULL, key TEXT NOT NULL, tool TEXT NOT NULL, summary TEXT NOT NULL,
        ok INTEGER NOT NULL)''',
]
SIDE_EFFECTS = {'send_email', 'prepare_message', 'call_phone', 'create_calendar_event', 'create_reminder',
                'complete_reminder', 'run_shortcut'}
FOLLOWUP = re.compile(r'^(?:bitte\s+)?(?:mach(?:e)?\s+(?:weiter|das|es|daraus)|weiter\b|fortsetzen|setz\w*\s+fort|nochmal|'
                      r'erneut|versuch|ändere|änder|ergänze|kürze|verlängere|korrigiere|überarbeite|speicher\w*\s+(?:es|das|sie|ihn)|'
                      r'(?:und\s+)?(?:jetzt|nun)\s+(?:als|noch)|als\s+(?:pdf|word|excel)|ja\b|continue|try again|save it|change it)', re.I)
RESUME = re.compile(r'^(?:bitte\s+)?(?:mach(?:e)?\s+weiter|weiter(?:machen)?\b|fortsetzen|setz\w*\s+(?:die aufgabe\s+)?fort|'
                    r'continue|resume)', re.I)


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def action_key(tool: str, args: dict) -> str:
    normalized = json.dumps(args, sort_keys=True, ensure_ascii=False).lower()
    normalized = re.sub(r'\s+', ' ', normalized)
    return hashlib.sha256(f'{tool}:{normalized}'.encode()).hexdigest()


class TaskJournal:
    def __init__(self, connect: Callable):
        self.connect = connect
        with self.connect() as db:
            for statement in SCHEMA:
                db.execute(statement)

    # -- Aufgaben ------------------------------------------------------------------------------------
    def record(self, goal: str, mode: str, actions: list, open_steps: list[str], finished: bool, cancelled: bool,
               reason: str = '', resumed_from: int | None = None) -> int:
        steps, artifacts = [], []
        for action in actions:
            state = 'erledigt' if action.ok else 'abgelehnt' if action.declined else 'fehlgeschlagen'
            steps.append({'tool': action.tool, 'summary': action.summary[:200], 'status': state, 'verified': action.verified})
            path = (getattr(action, 'data', None) or {}).get('path')
            if action.ok and path and path not in artifacts:
                artifacts.append(path)
        failed = [s for s in steps if s['status'] == 'fehlgeschlagen']
        # Ein später erfolgreicher Schritt mit GLEICHEM Inhalt behebt einen Fehlschlag – ein anderer nicht.
        unresolved = [f for f in failed if not any(s['status'] == 'erledigt' and s['tool'] == f['tool'] and
                                                    s['summary'] == f['summary'] for s in steps)]
        if cancelled:
            status = 'abgebrochen'
        elif not finished or open_steps:
            status = 'offen'
        elif unresolved or any(s['status'] == 'abgelehnt' for s in steps):
            status = 'teilweise'
        elif steps:
            status = 'erledigt'
        else:
            status = 'ohne_aktion'
        with self.connect() as db:
            return db.execute('INSERT INTO tasks(created_at, goal, mode, status, steps, open_steps, artifacts, reason, resumed_from) '
                              'VALUES (?,?,?,?,?,?,?,?,?)',
                              (now(), goal[:2000], mode, status, json.dumps(steps, ensure_ascii=False),
                               json.dumps(open_steps, ensure_ascii=False), json.dumps(artifacts, ensure_ascii=False),
                               reason[:200], resumed_from)).lastrowid

    def recent(self, hours: float = 12, limit: int = 5) -> list[dict]:
        since = (datetime.now(timezone.utc) - timedelta(hours=hours)).isoformat()
        with self.connect() as db:
            cursor = db.execute("SELECT * FROM tasks WHERE created_at>=? AND status!='ohne_aktion' ORDER BY id DESC LIMIT ?",
                                (since, limit))
            names = [c[0] for c in cursor.description]
            rows = [dict(zip(names, row)) for row in cursor.fetchall()]
        for row in rows:
            for key in ('steps', 'open_steps', 'artifacts'):
                row[key] = json.loads(row[key])
        return rows

    def unfinished(self) -> dict | None:
        """Letzte nicht abgeschlossene Aufgabe (abgebrochen, offen, teilweise), die noch nicht fortgesetzt wurde."""
        recent = self.recent(hours=48, limit=10)
        resumed = {t['resumed_from'] for t in recent if t['resumed_from']}
        for task in recent:
            if task['status'] in ('abgebrochen', 'offen', 'teilweise') and task['id'] not in resumed:
                return task
            if task['status'] == 'erledigt':
                return None          # danach ist nichts mehr offen
        return None

    def context_for(self, text: str) -> tuple[str, int | None]:
        """Zusammenhang für einen Folgeauftrag. Gibt (Text für den Prompt, fortgesetzte Aufgabe) zurück."""
        stripped = text.strip()
        if RESUME.match(stripped):
            task = self.unfinished()
            if task:
                return self._describe(task, resume=True), task['id']
        if not FOLLOWUP.match(stripped) and not re.search(r'\b(es|das|die datei|das dokument|sie|it|that)\b', stripped, re.I):
            return '', None
        recent = self.recent(hours=6, limit=1)
        return (self._describe(recent[0], resume=False), None) if recent else ('', None)

    @staticmethod
    def _describe(task: dict, resume: bool) -> str:
        lines = [f'Vorherige Aufgabe ({task["status"]}): {task["goal"][:400]}']
        done = [s for s in task['steps'] if s['status'] == 'erledigt']
        failed = [s for s in task['steps'] if s['status'] == 'fehlgeschlagen']
        if done:
            lines.append('Bereits erledigt (NICHT wiederholen): ' + '; '.join(s['summary'][:100] for s in done[:8]))
        if failed:
            lines.append('Fehlgeschlagen: ' + '; '.join(s['summary'][:100] for s in failed[:5]))
        if task['open_steps']:
            lines.append('Noch offen: ' + '; '.join(task['open_steps'][:6]))
        if task['artifacts']:
            lines.append('Erzeugte Dateien (mit „es“/„das“ ist meist die letzte gemeint): ' + ', '.join(task['artifacts'][-4:]))
        if resume:
            lines.append('Setze diese Aufgabe fort: nur die offenen oder fehlgeschlagenen Teile erledigen.')
        return '\n'.join(lines)

    # -- Aktionen mit Außenwirkung ------------------------------------------------------------------
    def already_done(self, tool: str, args: dict, hours: float = 24) -> str | None:
        """Zeitpunkt der gleichen, bereits erfolgreich ausgeführten Aktion – oder None."""
        if tool not in SIDE_EFFECTS:
            return None
        since = (datetime.now(timezone.utc) - timedelta(hours=hours)).isoformat()
        with self.connect() as db:
            row = db.execute('SELECT created_at FROM side_effects WHERE key=? AND ok=1 AND created_at>=? ORDER BY id DESC',
                             (action_key(tool, args), since)).fetchone()
        if not row:
            return None
        return datetime.fromisoformat(row[0]).astimezone().strftime('%d.%m. %H:%M')

    def note_side_effect(self, tool: str, args: dict, summary: str, ok: bool) -> None:
        if tool in SIDE_EFFECTS:
            with self.connect() as db:
                db.execute('INSERT INTO side_effects(created_at, key, tool, summary, ok) VALUES (?,?,?,?,?)',
                           (now(), action_key(tool, args), tool, summary[:200], int(ok)))
