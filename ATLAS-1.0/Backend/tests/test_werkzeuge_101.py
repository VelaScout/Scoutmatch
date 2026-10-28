"""Atlas 1.0.1: Pfadfehler kleiner Modelle, neue Dateien ohne Rückfrage, Suche mit mehreren Diensten.
Fälle aus den Mac-Testläufen (powerpoint_erstellen, markdown_liste, teilweise_fehler, ordner_und_datei, recherche)."""
import tempfile
import unittest
import urllib.error
from pathlib import Path

from atlas import tools as t
from atlas.tools import CONFIRM, SAFE, Environment, ToolError


class PfadTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name).resolve() / 'home'
        for name in ('Desktop', 'Documents', 'Downloads'):
            (self.home / name).mkdir(parents=True)
        self.env = Environment(home=self.home, roots=[self.home], is_mac=False)

    def tearDown(self):
        self.tmp.cleanup()

    def test_placeholder_users(self):
        for user in ('username', 'you', 'user'):
            self.assertEqual(self.env.resolve(f'/Users/{user}/Desktop/einkauf.md', for_write=True),
                             self.home / 'Desktop' / 'einkauf.md')

    def test_duplicate_and_sentence_folders(self):
        self.assertEqual(self.env.resolve('~/Documents/Dokumente/gibtsnicht.pdf'), self.home / 'Documents' / 'gibtsnicht.pdf')
        self.assertEqual(self.env.resolve('~/Desktop/Erstelle_Dokumente/Atlas-Plan.pptx', for_write=True),
                         self.home / 'Documents' / 'Atlas-Plan.pptx')
        self.assertEqual(self.env.resolve('~/Schreibtisch/einkauf.md', for_write=True), self.home / 'Desktop' / 'einkauf.md')

    def test_wanted_folders_stay(self):
        self.assertEqual(self.env.resolve('~/Documents/Ablage/Bilder/foto.jpg', for_write=True),
                         self.home / 'Documents' / 'Ablage' / 'Bilder' / 'foto.jpg')
        (self.home / 'Documents' / 'Alte_Dokumente').mkdir()
        self.assertEqual(self.env.resolve('~/Documents/Alte_Dokumente/a.txt', for_write=True),
                         self.home / 'Documents' / 'Alte_Dokumente' / 'a.txt')
        self.assertEqual(self.env.resolve('~/Documents/Projekt Dokumente/a.txt', for_write=True),
                         self.home / 'Documents' / 'Projekt Dokumente' / 'a.txt')

    def test_outside_still_blocked(self):
        with self.assertRaises(ToolError):
            self.env.resolve('/etc/hosts')

    def test_new_file_needs_no_confirmation_even_with_overwrite(self):
        tool = t.build_tools(self.env)['write_file']
        self.assertEqual(tool.risk_for({'path': '~/Documents/Atlas-Test/notiz.txt', 'content': 'x', 'overwrite': True}), SAFE)
        (self.home / 'Documents' / 'alt.txt').write_text('bleibt')
        self.assertEqual(tool.risk_for({'path': '~/Documents/alt.txt', 'content': 'x', 'overwrite': True}), CONFIRM)


class SucheTests(unittest.TestCase):
    def test_falls_back_to_next_provider(self):
        calls = []

        def fetch(url, timeout):
            calls.append(url)
            if len(calls) == 1:
                raise urllib.error.URLError('blockiert')
            return ('<rss><channel><item><title>Präsident von Frankreich</title><link>https://example.org/a</link>'
                    '<description>Info</description></item></channel></rss>')
        with tempfile.TemporaryDirectory() as folder:
            env = Environment(home=Path(folder), roots=[Path(folder)], fetch=fetch, is_mac=False)
            result = t.search_web(env, 'Präsident Frankreich')
        self.assertTrue(result.ok, result.output)
        self.assertGreaterEqual(len(calls), 2)


if __name__ == '__main__':
    unittest.main()


class DenkmodellTests(unittest.TestCase):
    def test_reasoning_model_follows_settings_and_prefers_8b(self):
        from fake_ollama import FakeOllama
        from atlas import llm
        fake = FakeOllama(models=('qwen3:4b', 'qwen3:8b', 'qwen3:14b'))
        try:
            client = llm.Ollama(base=fake.url)
            self.assertEqual(client.reasoning_model(), 'qwen3:8b')     # 14B nur nach Messung
            client.preferred = {'reasoning': 'qwen3:14b'}
            self.assertEqual(client.reasoning_model(), 'qwen3:14b')
            client.preferred = {'reasoning': 'qwen3:32b'}               # nicht installiert → Standard
            self.assertEqual(client.reasoning_model(), 'qwen3:8b')
        finally:
            fake.close()
