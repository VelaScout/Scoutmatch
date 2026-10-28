#!/usr/bin/env python3
"""Offline-Qualitätsbericht: gespeichertes Wissen, Belege, Lücken und Suchindex."""
import argparse
import contextlib
import json
import os
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from atlas.knowledge import Knowledge


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument('--datenbank', type=Path, default=Path(os.environ.get('ATLAS_DATA_DIR', str(Path.home()/'.atlas-ai')))/'atlas.db')
    parser.add_argument('--alter-tage', type=int, default=365)
    args = parser.parse_args(argv)
    if not args.datenbank.is_file():
        parser.error('Keine bestehende ATLAS-Datenbank gefunden. Zuerst ATLAS installieren/starten.')

    @contextlib.contextmanager
    def connect():
        db = sqlite3.connect(args.datenbank, timeout=15)
        try:
            with db:
                yield db
        finally:
            db.close()
    report = Knowledge(connect).audit(args.alter_tage)
    print(json.dumps(report, indent=2, ensure_ascii=False))
    print('Hinweis: Eine Quellen-URL ist kein Wahrheitsbeweis; Stichproben und Quellenprüfung bleiben notwendig.')
    return 0

if __name__ == '__main__':
    sys.exit(main())
