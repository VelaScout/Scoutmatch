"""Korrekturen nach Ihrem Mac-Testlauf mit 0.8.0 (markdown_liste, teilweise_fehler, recherche, Diagnose „rechnung“).

Echt: Pfadauflösung, Rechnen, Suche-Auswertung, Agentenablauf mit Dateien. Simuliert: Internet (feste Antworten)
und die Entscheidungen des Sprachmodells (FakeOllama). Ob das echte Modell sich jetzt richtig verhält,
zeigt erst der nächste MAC_TESTEN-Lauf.
"""
import tempfile
import threading
import unittest
import urllib.error
from pathlib import Path

from atlas import agent as a
from atlas import llm
from atlas.intents import plan
from atlas.research import research
from atlas.tools import Environment, build_tools, search_web
from fake_ollama import FakeOllama, answer, tool_call

BING = ('<?xml version="1.0"?><rss><channel><item><title>Präsident Frankreichs</title>'
        '<link>https://example.org/praesident</link><description>Der Präsident der Republik …</description></item>'
        '</channel></rss>')


class FeedbackTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name).resolve()
        for name in ('Desktop', 'Documents'):
            (self.home / name).mkdir()

    def env(self, fetch=None):
        return Environment(home=self.home, roots=[self.home], is_mac=False, fetch=fetch)

    def test_german_folder_names_land_in_the_real_folders(self):
        env = self.env()
        build_tools(env)['write_file'].func(path='~/Schreibtisch/einkauf.md', content='- Milch\n- Brot\n- Eier')
        self.assertTrue((self.home / 'Desktop' / 'einkauf.md').is_file())
        self.assertFalse((self.home / 'Schreibtisch').exists())
        self.assertEqual(env.resolve('~/Dokumente/x.txt', for_write=True), self.home / 'Documents' / 'x.txt')

    def test_calculation_with_format_hint_is_exact(self):
        self.assertEqual(plan('Was ist 17 mal 23? Antworte nur mit der Zahl.'), {'kind': 'answer', 'answer': '391.'})
        self.assertEqual(plan('Was ist 2+2? Und erkläre mir dann Quantenphysik.'), {'kind': 'chat'})

    def test_after_a_failed_step_the_other_parts_are_still_done(self):
        ollama = FakeOllama()
        self.addCleanup(ollama.close)
        agent = a.Agent(llm.Ollama(base=ollama.url), build_tools(self.env()), a.Bridge(),
                        limits=a.Limits(max_rounds=6, seconds=30, native_timeout=2))
        ollama.script = [tool_call('read_file', path='~/Documents/gibtsnicht.pdf'),
                         answer('Die Datei gibt es nicht.'),                       # Modell hört zu früh auf …
                         tool_call('create_folder', path='~/Documents/Bericht-Ablage'),
                         answer('Die PDF gibt es nicht; den Ordner Bericht-Ablage habe ich angelegt.')]
        events = list(agent.run(a.Request(system='ATLAS', history=[{'role': 'user', 'content':
            'Lies Dokumente/gibtsnicht.pdf und lege danach in Dokumente einen Ordner Bericht-Ablage an.'}]), threading.Event()))
        self.assertTrue((self.home / 'Documents' / 'Bericht-Ablage').is_dir())   # … wird einmal zum Weitermachen aufgefordert
        self.assertIn('übrigen Teile', ollama.chat_requests()[2]['messages'][-1]['content'])
        report = next(e for e in events if e['type'] == 'report')
        self.assertTrue(report['failed'] and report['done'])
        failed_step = next(e for e in events if e['type'] == 'step' and e['status'] == 'fehlgeschlagen')
        self.assertIn('Nicht gefunden', failed_step['note'])

    def test_search_falls_back_and_names_the_cause(self):
        def blocked_then_bing(url, timeout):
            if 'duckduckgo.com/html' in url:
                return '<html>Unfortunately, bots use DuckDuckGo too.</html>'          # Schutzseite ohne Treffer
            if 'lite.duckduckgo' in url:
                raise urllib.error.URLError('[SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed')
            if 'bing.com' in url:
                return BING
            raise AssertionError(url)
        result = search_web(self.env(blocked_then_bing), 'Präsident Frankreich')
        self.assertTrue(result.ok)
        self.assertEqual(result.data['provider'], 'Bing')
        self.assertEqual(result.data['results'][0]['url'], 'https://example.org/praesident')
        self.assertIn('Zertifikatsfehler', result.data['attempts'][1])

        def nothing(url, timeout):
            return '<html>keine Treffer</html>'
        blocked = research(self.env(nothing), 'Präsident Frankreich')
        self.assertFalse(blocked.ok)
        self.assertIn('Recherche ohne Ergebnis', blocked.output)                 # nicht fälschlich „offline“
        self.assertFalse(blocked.data['offline'])

        def offline(url, timeout):
            raise urllib.error.URLError('nodename nor servname provided')
        down = research(self.env(offline), 'Präsident Frankreich')
        self.assertTrue(down.data['offline'])
        self.assertIn('Internet nicht erreichbar', down.output)


if __name__ == '__main__':
    unittest.main()
