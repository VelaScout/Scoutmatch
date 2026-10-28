#!/usr/bin/env python3
"""Nicht-destruktiver Nachweis, dass die Lernpakete mit ATLAS Scheduler kompatibel sind."""
import argparse, sqlite3
from pathlib import Path
p = argparse.ArgumentParser()
p.add_argument('--datenbank', type=Path, required=True)
args = p.parse_args()
with sqlite3.connect(args.datenbank) as db:
    items = db.execute("SELECT kind, status, count(*) FROM evolution_jobs WHERE origin='wissenspaket' GROUP BY kind,status").fetchall()
    valid = {'wartet', 'läuft', 'fertig', 'abgebrochen', 'fehlgeschlagen', 'blockiert'}
    assert all(kind == 'topic' or status in {'abgebrochen','fehlgeschlagen'} for kind,status,_ in items), items
    assert all(status in valid for _,status,_ in items), items
    total = sum(n for kind,status,n in items if kind == 'topic')
    assert total == 193, f'Erwartet 193 Wissensjobs, gefunden {total}'
    print(f'OK: {total} Scheduler-kompatible Lernaufträge in {args.datenbank}')
    for kind,status,n in items: print(f'  {kind} / {status}: {n}')
