"""Auswertung des Mac-Testlaufs: Datenerhalt nach Neustart und Zusammenfassung mit eindeutigen Zuständen.
Echt: SQLite (nur lesend), Dateien, Aufruf der Module wie in MAC_TESTEN.command."""
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from atlas.persistence_check import compare, count

BACKEND = Path(__file__).resolve().parent.parent


class MacReportTests(unittest.TestCase):
    def test_restart_check_detects_lost_entries(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'atlas.db'
            db = sqlite3.connect(path)
            db.execute('CREATE TABLE memories (id INTEGER PRIMARY KEY, content TEXT)')
            db.executemany('INSERT INTO memories(content) VALUES (?)', [('a',), ('b',)])
            db.commit()
            before = count(path)
            self.assertEqual(before, {'memories': 2})
            self.assertEqual(compare(before, count(path))['status'], 'BESTANDEN')
            db.execute('DELETE FROM memories WHERE id=1')
            db.commit()
            db.close()
            result = compare(before, count(path))
            self.assertEqual((result['status'], result['lost']), ('FEHLGESCHLAGEN', {'memories': (2, 1)}))

    def test_summary_shows_three_states_and_split_timings(self):
        with tempfile.TemporaryDirectory() as tmp:
            build = Path(tmp)
            (build / 'MAC-ECHTE-MODELLTESTS.json').write_text(json.dumps({
                'executed': True, 'installed_models': ['qwen3:4b-instruct'], 'results': [
                    {'case': 'rechnen', 'status': 'BESTANDEN', 'passed': True, 'first_feedback_s': 0.1, 'total_s': 0.2},
                    {'case': 'word_aendern', 'status': 'FEHLGESCHLAGEN', 'passed': False, 'first_feedback_s': 0.9, 'total_s': 21.0},
                    {'case': 'recherche_quellen', 'status': 'NICHT AUSGEFÜHRT', 'passed': False, 'first_feedback_s': 1.0, 'total_s': 3.0}]}))
            (build / 'MAC-NEUSTART.json').write_text(json.dumps({'status': 'BESTANDEN'}))
            (build / 'MAC-SANDBOX.json').write_text(json.dumps({'available': True, 'none': 'Variante 1', 'localhost': 'Variante 1'}))
            out = subprocess.run([sys.executable, '-m', 'atlas.summary', str(build)], cwd=BACKEND, capture_output=True,
                                 text=True, env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'}).stdout
        self.assertIn('1 BESTANDEN, 1 FEHLGESCHLAGEN, 1 NICHT AUSGEFÜHRT', out)
        self.assertIn('erste Rückmeldung 0.9 s, vollständiges Ergebnis 3.0 s', out)
        self.assertIn('-- recherche_quelle', out)
        self.assertIn('Neustart-Datenerhalt: BESTANDEN', out)
        self.assertIn('Sandbox: Fähigkeiten Variante 1', out)
        self.assertTrue(all(len(line) <= 80 for line in out.splitlines()), out)


if __name__ == '__main__':
    unittest.main()
