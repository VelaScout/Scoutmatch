"""Selbsttest der Optimierung: Modellplan je Arbeitsspeicher, Messung über ATLAS, Auswahl, Einstellungen mit Sicherung."""
import json
import pathlib
import tempfile
import unittest

import atlas_gesamtpruefung as g
import atlas_optimierung as o


class FakeQuelle:
    """Antwortet je nach eingestelltem Denkmodell richtig/falsch und unterschiedlich schnell."""
    def __init__(self, quality, seconds):
        self.quality, self.seconds = quality, seconds
        self.cases = {(c['frage'][-1]['content'] if isinstance(c['frage'], list) else c['frage']): c for c in g.KATALOG}

    def frage(self, history):
        model = o.einstellungen_lesen().get('reasoning_model')
        case = self.cases[history[-1]['content']]
        good = self.quality[model]
        return {'antwort': case['richtig'] if good else case['falsch'], 'fehler': '', 'erste_ausgabe_s': None,
                'gesamt_s': self.seconds[model], 'modus': 'deliberate', 'modell': model}


class OptimierungTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.old = o.SETTINGS
        o.SETTINGS = pathlib.Path(self.tmp.name) / 'settings.json'
        o.SETTINGS.write_text(json.dumps({'chat_model': 'qwen3:4b-instruct-2507-q4_K_M', 'allowed_folders': ['x']}))
        self.swap = o.swap_mb
        o.swap_mb = lambda: 0.0

    def tearDown(self):
        o.SETTINGS = self.old
        o.swap_mb = self.swap
        self.tmp.cleanup()

    def test_plan_for_16_gb(self):
        plan = o.plan_fuer(16)
        self.assertEqual(plan['denken'], ['qwen3:4b', 'qwen3:8b', 'qwen3:14b'])
        self.assertEqual(plan['bild'], 'gemma3:4b')
        self.assertNotIn('qwen3:30b', plan['denken'])

    def test_best_model_that_runs_smoothly_wins(self):
        quelle = FakeQuelle({'qwen3:4b': False, 'qwen3:8b': True, 'qwen3:14b': True},
                            {'qwen3:4b': 10, 'qwen3:8b': 30, 'qwen3:14b': 200})
        results = [o.messen(m, quelle, ausgabe=lambda *_: None) for m in ('qwen3:4b', 'qwen3:8b', 'qwen3:14b')]
        self.assertEqual(results[1]['bestanden'], results[1]['aufgaben'])
        self.assertFalse(o.geeignet(results[2]))            # 200 s Median: zu langsam
        self.assertEqual(o.waehlen(results)['modell'], 'qwen3:8b')

    def test_too_slow_model_is_stopped_early(self):
        quelle = FakeQuelle({'qwen3:14b': True}, {'qwen3:14b': 400})
        result = o.messen('qwen3:14b', quelle, ausgabe=lambda *_: None)
        self.assertEqual(result['gefragt'], 1)
        self.assertIn('zu langsam', result['abbruch'])

    def test_swapping_model_is_rejected(self):
        values = iter([0.0, 4000.0])
        o.swap_mb = lambda: next(values)
        quelle = FakeQuelle({'qwen3:14b': True}, {'qwen3:14b': 20})
        self.assertFalse(o.geeignet(o.messen('qwen3:14b', quelle, ausgabe=lambda *_: None)))

    def test_settings_keep_other_keys_and_backup(self):
        backup = o.sichern()
        data = o.einstellungen_lesen()
        data['reasoning_model'] = 'qwen3:8b'
        o.einstellungen_schreiben(data)
        saved = json.loads(o.SETTINGS.read_text())
        self.assertEqual(saved['allowed_folders'], ['x'])
        self.assertEqual(saved['reasoning_model'], 'qwen3:8b')
        self.assertTrue(backup.exists())
        self.assertNotIn('reasoning_model', json.loads(backup.read_text()))

    def test_version_check(self):
        self.assertTrue(o.mindestens('1.0.3'))
        self.assertTrue(o.mindestens('1.1.0'))
        self.assertFalse(o.mindestens('1.0.2'))
        self.assertFalse(o.mindestens(''))

    def test_report(self):
        with tempfile.TemporaryDirectory() as folder:
            r = {'modell': 'qwen3:8b', 'bestanden': 11, 'gefragt': 11, 'aufgaben': 11, 'median_s': 30, 'max_s': 50,
                 'swap_zuwachs_mb': 0, 'abbruch': ''}
            text = o.bericht(pathlib.Path(folder), {'ram': 16, 'frei': 200}, [r], r, None, None, None)
        self.assertIn('Eingestellt: qwen3:8b', text)


if __name__ == '__main__':
    unittest.main()
