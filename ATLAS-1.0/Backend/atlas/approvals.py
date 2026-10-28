"""Freigabesystem: Alles, was ATLAS dauerhaft verändert, wartet auf die Entscheidung des Nutzers.

Arten: 'skill' (neue Fähigkeit aktivieren), 'package' (Python-Bibliothek installieren),
'hint' (gelernte Arbeitsanweisung aktivieren), 'code' (getestete Code-Änderung übernehmen).
Status: wartet → freigegeben/aktiv | abgelehnt | fehlgeschlagen | zurueckgesetzt
"""
from __future__ import annotations

import json
from collections.abc import Callable
from datetime import datetime, timezone

SCHEMA = '''CREATE TABLE IF NOT EXISTS proposals (
    id INTEGER PRIMARY KEY, kind TEXT NOT NULL, title TEXT NOT NULL, detail TEXT NOT NULL,
    status TEXT NOT NULL, security_relevant INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL,
    decided_at TEXT, result TEXT NOT NULL DEFAULT '')'''


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


class Approvals:
    def __init__(self, connect: Callable):
        self.connect = connect
        self.handlers: dict[str, Callable[[dict], str]] = {}
        with self.connect() as db:
            db.execute(SCHEMA)

    def register(self, kind: str, handler: Callable[[dict], str]) -> None:
        """handler(detail) führt die freigegebene Änderung aus und gibt eine Beschreibung zurück."""
        self.handlers[kind] = handler

    def propose(self, kind: str, title: str, detail: dict, security_relevant: bool = False) -> int:
        with self.connect() as db:
            duplicate = db.execute("SELECT id FROM proposals WHERE kind=? AND title=? AND status='wartet'",
                                   (kind, title)).fetchone()
            if duplicate:
                return duplicate[0]
            cursor = db.execute('INSERT INTO proposals(kind, title, detail, status, security_relevant, created_at) '
                                'VALUES (?,?,?,?,?,?)', (kind, title[:200], json.dumps(detail, ensure_ascii=False),
                                                         'wartet', int(security_relevant), now()))
            return cursor.lastrowid

    def get(self, proposal_id: int) -> dict | None:
        with self.connect() as db:
            cursor = db.execute('SELECT * FROM proposals WHERE id=?', (proposal_id,))
            row = cursor.fetchone()
            if not row:
                return None
            item = dict(zip([c[0] for c in cursor.description], row))
        item['detail'] = json.loads(item['detail'])
        return item

    def list(self, status: str | None = None, limit: int = 100) -> list[dict]:
        with self.connect() as db:
            query = 'SELECT id FROM proposals' + (' WHERE status=?' if status else '') + ' ORDER BY id DESC LIMIT ?'
            ids = [r[0] for r in db.execute(query, ((status, limit) if status else (limit,))).fetchall()]
        return [self.get(i) for i in ids]

    def pending(self) -> list[dict]:
        return self.list('wartet')

    def decide(self, proposal_id: int, approved: bool) -> dict:
        """Nur der Nutzer ruft das auf (über die App). Ohne Freigabe wird nichts ausgeführt."""
        item = self.get(proposal_id)
        if not item:
            raise ValueError('Vorschlag nicht gefunden.')
        if item['status'] != 'wartet':
            raise ValueError(f'Vorschlag ist bereits {item["status"]}.')
        if not approved:
            self._set(proposal_id, 'abgelehnt', 'Vom Nutzer abgelehnt.')
            return self.get(proposal_id)
        handler = self.handlers.get(item['kind'])
        if handler is None:
            raise ValueError(f'Keine Ausführung für Art {item["kind"]}.')
        try:
            result = handler(item['detail'])
            self._set(proposal_id, 'aktiv', result)
        except Exception as exc:  # fehlgeschlagene Übernahme wird festgehalten, nichts bleibt halb aktiv
            self._set(proposal_id, 'fehlgeschlagen', f'{type(exc).__name__}: {exc}'[:1000])
        return self.get(proposal_id)

    def mark(self, proposal_id: int, status: str, result: str = '') -> None:
        self._set(proposal_id, status, result)

    def _set(self, proposal_id: int, status: str, result: str) -> None:
        with self.connect() as db:
            db.execute('UPDATE proposals SET status=?, result=?, decided_at=? WHERE id=?',
                       (status, result[:2000], now(), proposal_id))
