"""Datenerhalt über einen Neustart prüfen (MAC_TESTEN.command): Einträge je Tabelle zählen – nur lesend.

Aufruf: python3 -m atlas.persistence_check count <datei.json>
        python3 -m atlas.persistence_check compare <vorher.json> <nachher.json> <ergebnis.json>
"""
import json
import os
import sqlite3
import sys
from pathlib import Path

TABLES = ('messages', 'memories', 'experiences', 'rules', 'tasks', 'skills', 'knowledge_facts', 'proposals', 'cloud_usage')


def count(db_path: Path) -> dict:
    if not db_path.is_file():
        return {}
    db = sqlite3.connect(f'file:{db_path}?mode=ro', uri=True)
    try:
        names = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        return {t: db.execute(f'SELECT count(*) FROM {t}').fetchone()[0] for t in TABLES if t in names}
    finally:
        db.close()


def compare(before: dict, after: dict) -> dict:
    lost = {t: (n, after.get(t, 0)) for t, n in before.items() if after.get(t, 0) < n}
    return {'status': 'FEHLGESCHLAGEN' if lost else 'BESTANDEN', 'lost': lost, 'before': before, 'after': after}


def main() -> int:
    data = Path(os.environ.get('ATLAS_DATA_DIR', str(Path.home() / '.atlas-ai'))) / 'atlas.db'
    if sys.argv[1] == 'count':
        Path(sys.argv[2]).write_text(json.dumps(count(data)), encoding='utf-8')
        return 0
    before, after = (json.loads(Path(p).read_text(encoding='utf-8')) for p in sys.argv[2:4])
    result = compare(before, after)
    Path(sys.argv[4]).write_text(json.dumps(result, ensure_ascii=False), encoding='utf-8')
    print(f"Neustart-Datenerhalt: {result['status']}" + (f" – verloren: {result['lost']}" if result['lost'] else ''))
    return 0 if result['status'] == 'BESTANDEN' else 1


if __name__ == '__main__':
    raise SystemExit(main())
