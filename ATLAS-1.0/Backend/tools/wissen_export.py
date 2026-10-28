#!/usr/bin/env python3
"""Export ATLAS knowledge with provenance to a portable JSON file, read-only."""
import argparse
import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path


def export(db_path: Path, output: Path):
    if not db_path.is_file():
        raise FileNotFoundError(f'Datenbank fehlt: {db_path}')
    db = sqlite3.connect(f'file:{db_path.resolve()}?mode=ro', uri=True)
    db.row_factory = sqlite3.Row
    try:
        topics = [dict(r) for r in db.execute('SELECT * FROM knowledge_topics ORDER BY id')]
        facts = [dict(r) for r in db.execute('SELECT * FROM knowledge_facts ORDER BY id')]
    finally:
        db.close()
    output.parent.mkdir(parents=True, exist_ok=True)
    tmp = output.with_suffix(output.suffix + '.tmp')
    tmp.write_text(json.dumps({'format':'atlas-knowledge-v1', 'exported_at':datetime.now(timezone.utc).isoformat(), 'topics':topics, 'facts':facts}, ensure_ascii=False, indent=2), encoding='utf-8')
    tmp.replace(output)
    return len(topics), len(facts)

if __name__ == '__main__':
    p=argparse.ArgumentParser(description='Exportiere ATLAS-Wissen mit Quellen als JSON (nur lesen)')
    p.add_argument('--datenbank', type=Path, default=Path.home()/'.atlas-ai'/'atlas.db')
    p.add_argument('--ausgabe', type=Path, default=Path.home()/'Downloads'/'atlas-wissen-export.json')
    a=p.parse_args()
    t,f=export(a.datenbank.expanduser(), a.ausgabe.expanduser())
    print(f'Exportiert: {t} Themen, {f} Fakten -> {a.ausgabe}')
