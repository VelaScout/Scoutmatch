"""Prüft die Prüflogik der echten Modelltests (atlas.realtests) und zwei mehrstufige Abläufe.

Ein simuliertes Modell spielt die richtigen Werkzeugschritte vor; Dateien, Verschieben, Terminal
(echtes python3 -m unittest) und die Ergebnisprüfung laufen echt. Das beweist NICHT, dass Qwen
diese Schritte selbst findet – das zeigt nur MAC_TESTEN.command mit dem echten Modell.
"""
import tempfile
import unittest
from pathlib import Path

from atlas import agent as a
from atlas import llm
from atlas import realtests as r
from atlas.tools import Environment, build_tools
from fake_ollama import FakeOllama, answer, tool_call


class RealTestLogicTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name).resolve() / 'home'
        r.prepare(self.home)
        self.ollama = FakeOllama()
        self.addCleanup(self.ollama.close)
        self.agent = a.Agent(llm.Ollama(base=self.ollama.url),
                             build_tools(Environment(home=self.home, roots=[self.home], is_mac=False)), a.Bridge(),
                             limits=a.Limits(max_rounds=12, seconds=60, native_timeout=5))
        self.cases = {name: (prompt, approve, check) for name, prompt, approve, check in r.cases(self.home)}

    def run_case(self, name):
        prompt, approve, check = self.cases[name]
        return check(r.drive(self.agent, prompt, approve))

    def test_sorting_folder_passes_only_when_really_sorted(self):
        self.ollama.script = [answer('{"steps": ["Ordner ansehen", "Unterordner anlegen", "Dateien verschieben"]}')]
        self.assertFalse(self.run_case('ordner_sortieren'))       # Modell tut nichts → durchgefallen
        moves = []
        for folder, files in (('PDF', ['rechnung.pdf', 'vertrag.pdf']), ('Bilder', ['urlaub.jpg']), ('Texte', ['notiz.txt'])):
            moves.append(tool_call('create_folder', path=f'~/Documents/Ablage/{folder}'))
            moves += [tool_call('move_path', source=f'~/Documents/Ablage/{f}', destination=f'~/Documents/Ablage/{folder}')
                      for f in files]
        self.ollama.script = [answer('{"steps": ["Sortieren"]}'), tool_call('list_directory', path='~/Documents/Ablage')] + \
            moves + [answer('Vier Dateien in PDF, Bilder und Texte sortiert.')]
        self.assertTrue(self.run_case('ordner_sortieren'))
        self.assertTrue((self.home / 'Documents/Ablage/PDF/vertrag.pdf').is_file())

    def test_fixing_bug_passes_only_when_tests_really_pass(self):
        self.assertFalse(self.run_case('fehler_beheben'))
        fixed = 'def netto(brutto, steuer=0.19):\n    return brutto / (1 + steuer)\n'
        self.ollama.script = [
            answer('{"steps": ["Projekt untersuchen", "Tests ausführen", "Fehler beheben", "Tests wiederholen"]}'),
            tool_call('inspect_project', path='~/Code/rechner'),
            tool_call('run_command', command='python3 -m unittest discover -s tests -t .', folder='~/Code/rechner'),
            tool_call('read_file', path='~/Code/rechner/rechner.py'),
            tool_call('write_file', path='~/Code/rechner/rechner.py', content=fixed, overwrite=True),
            tool_call('run_command', command='python3 -m unittest discover -s tests -t .', folder='~/Code/rechner'),
            answer('Fehler gefunden: Es wurde mit statt durch (1 + Steuer) gerechnet. Behoben, alle Tests bestehen.'),
        ]
        prompt, approve, check = self.cases['fehler_beheben']
        result = r.drive(self.agent, prompt, approve)
        self.assertTrue(check(result))
        steps = [e for e in result['events'] if e['type'] == 'step' and e['status'] != 'läuft']
        statuses = [(e['tool'], e['status']) for e in steps]
        # Erster Testlauf schlägt fehl (ehrlich gemeldet), zweiter besteht.
        self.assertEqual([s for t, s in statuses if t == 'run_command'], ['fehlgeschlagen', 'erledigt'])
        report = next(e for e in result['events'] if e['type'] == 'report')
        self.assertEqual(report['failed'], [])     # roter Lauf wurde behoben → kein offener Fehler
        self.assertEqual(report['open'], [])

    def test_bug_fix_without_confirmation_changes_nothing(self):
        original = (self.home / 'Code/rechner/rechner.py').read_text()
        self.ollama.script = [
            answer('{"steps": ["Fehler beheben"]}'),
            tool_call('write_file', path='~/Code/rechner/rechner.py', content='kaputt', overwrite=True),
            answer('Ohne deine Zustimmung ändere ich nichts.'),
        ]
        prompt, _, check = self.cases['fehler_beheben']
        result = r.drive(self.agent, prompt, approve=False)
        self.assertEqual((self.home / 'Code/rechner/rechner.py').read_text(), original)
        self.assertFalse(check(result))


if __name__ == '__main__':
    unittest.main()
