"""Wissenspakete (aus Ihrem Paket 0.8.0_2): Vorschau, Einreihen ohne Doppelungen, Ausführung nur eingeschaltet.

Echt: SQLite, Lernplaner, Befehlszeile wie in WISSENSPAKETE-START.md. Simuliert: der Wissensaufbau selbst
(ein Ersatz-Handler statt Internet und Modell).
"""
import contextlib
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from atlas import wissenspakete as wp
from atlas.evolution import Scheduler

BACKEND = Path(__file__).resolve().parent.parent


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.db = Path(self.tmp.name) / 'atlas.db'

    @contextlib.contextmanager
    def connect(self):
        db = sqlite3.connect(self.db)
        try:
            with db:
                yield db
        finally:
            db.close()

    def cli(self, *args):
        return subprocess.run([sys.executable, str(BACKEND / 'tools' / 'wissenspakete.py'), '--datenbank', str(self.db), *args],
                              capture_output=True, text=True, timeout=60).stdout

    def test_preview_writes_nothing_and_queue_uses_the_real_job_kind(self):
        out = self.cli('--pakete', 'physik', 'sport')
        self.assertIn('Themen insgesamt: 27', out)
        self.assertIn('NUR VORSCHAU', out)
        self.assertFalse(self.db.exists())
        self.assertIn('aufgenommen: 27; bereits vorhanden: 0', self.cli('--pakete', 'physik', 'sport', '--einreihen'))
        self.assertIn('aufgenommen: 0; bereits vorhanden: 27', self.cli('--pakete', 'physik', 'sport', '--einreihen'))
        with self.connect() as db:
            kinds = db.execute('SELECT DISTINCT kind, origin, status FROM evolution_jobs').fetchall()
        self.assertEqual(kinds, [('topic', 'wissenspaket', 'wartet')])            # 'topic' – den kennt der Planer

    def test_packages_run_only_when_enabled_and_within_budget(self):
        learned = []
        scheduler = Scheduler(self.connect)
        scheduler.register('topic', lambda p, stop: learned.append(p['topic']) or {'status': 'gelernt'}, network=True)
        added, _ = wp.enqueue(scheduler, ['sport'])
        self.assertEqual(added, 12)
        self.assertIsNone(scheduler.run_next())                                  # Lernzyklen aus → nichts läuft
        self.assertEqual(learned, [])
        scheduler.submit('topic', {'topic': 'Mein eigenes Thema'})               # direkter Wunsch des Nutzers läuft
        self.assertEqual(scheduler.run_next()['status'], 'fertig')
        self.assertEqual(learned, ['Mein eigenes Thema'])
        scheduler.update(enabled=True)
        self.assertEqual(scheduler.run_next()['status'], 'fertig')
        self.assertEqual(learned[-1], 'Trainingslehre')
        with self.connect() as db:                                               # Tageslimit aufgebraucht
            db.execute("UPDATE evolution_jobs SET seconds=99999 WHERE origin='wissenspaket' AND status='fertig'")
        self.assertIsNone(scheduler.run_next())
        scheduler.update(allow_network=False, max_minutes_per_day=600)
        with self.connect() as db:
            db.execute("UPDATE evolution_jobs SET seconds=0")
        self.assertIsNone(scheduler.run_next())                                  # ohne Internet läuft nichts …
        waiting = [j for j in scheduler.jobs(100) if j['origin'] == 'wissenspaket' and j['status'] == 'wartet']
        self.assertEqual(len(waiting), 11)                                       # … und nichts geht verloren
        scheduler.update(allow_network=True)
        self.assertEqual(scheduler.run_next()['status'], 'fertig')

    def test_all_package_topics_are_reasonable(self):
        self.assertEqual(wp.preview(['alle'])['topics'], 193)
        for name, topics in wp.PACKAGES.items():
            self.assertEqual(len(topics), len(set(topics)), name)
            self.assertTrue(all(5 <= len(t) <= 80 for t in topics), name)


if __name__ == '__main__':
    unittest.main()
