"""Prüft die Prüflogik der echten Modelltests (atlas.realtests) und zwei mehrstufige Abläufe.

Ein simuliertes Modell spielt die richtigen Werkzeugschritte vor; Dateien, Verschieben, Terminal
(echtes python3 -m unittest) und die Ergebnisprüfung laufen echt. Das beweist NICHT, dass Qwen
diese Schritte selbst findet – das zeigt nur MAC_TESTEN.command mit dem echten Modell.
"""
import contextlib
import sqlite3
import tempfile
import unittest
from pathlib import Path

from atlas import agent as a
from atlas import llm
from atlas import realtests as r
from atlas.tasks import TaskJournal
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
                             build_tools(Environment(home=self.home, roots=[self.home], is_mac=False,
                                                     fetch=lambda url, timeout: (_ for _ in ()).throw(OSError('offline')))),
                             a.Bridge(), limits=a.Limits(max_rounds=12, seconds=60, native_timeout=5),
                             journal=TaskJournal(self.connect))
        self.cases = {name: (prompt, approve, check) for name, prompt, approve, check in r.cases(self.home)}

    @contextlib.contextmanager
    def connect(self):
        db = sqlite3.connect(Path(self.tmp.name) / 'journal.db')
        try:
            with db:
                yield db
        finally:
            db.close()

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

    def test_sorting_with_one_high_level_tool(self):
        self.ollama.script = [answer('{"steps": ["Ordner sortieren"]}'), tool_call('organize_folder', path='Dokumente/Ablage'),
                              answer('Sortiert: zwei PDFs, ein Bild, ein Text.')]
        self.assertTrue(self.run_case('ordner_sortieren'))

    def test_bug_fix_with_run_tests_and_replace(self):
        self.ollama.script = [
            answer('{"steps": ["Tests", "Korrektur", "Tests"]}'),
            tool_call('run_tests', path='~/Code/rechner'),
            tool_call('read_file', path='~/Code/rechner/rechner.py'),
            tool_call('replace_in_file', path='~/Code/rechner/rechner.py', old='brutto * (1 + steuer)', new='brutto / (1 + steuer)'),
            tool_call('run_tests', path='~/Code/rechner'),
            answer('Fehler behoben: Es wurde multipliziert statt geteilt. Alle Tests bestehen.'),
        ]
        self.assertTrue(self.run_case('fehler_beheben'))

    def test_new_everyday_cases_check_real_results(self):
        self.ollama.script = [tool_call('create_folder', path='~/Documents/Studium'), answer('Ordner Studium angelegt.')]
        self.assertTrue(self.run_case('ordner_studium'))
        self.ollama.script = [tool_call('write_file', path='~/Desktop/einkauf.md', content='# Einkauf\n- Milch\n- Brot\n- Eier\n'),
                              answer('Gespeichert.')]
        self.assertTrue(self.run_case('markdown_liste'))
        self.ollama.script = [tool_call('recent_files', folder='~/Downloads', days=1),
                              lambda body: answer('Gestern: ' + ('Angebot-Mueller.pdf' if 'Angebot-Mueller' in body['messages'][-1]['content'] else 'nichts'))]
        self.assertTrue(self.run_case('datei_von_gestern'))
        self.ollama.script = [tool_call('read_file', path='Dokumente/ausgaben.csv'),
                              tool_call('calculate', expression='1100+95+40+110'),
                              lambda body: answer('Die Summe ist ' + __import__('json').loads(body['messages'][-1]['content'])['output'])]
        self.assertTrue(self.run_case('csv_summe'))

    def test_compare_picks_best_model_and_applies_it(self):
        import json
        import os
        import subprocess
        import sys
        home = Path(self.tmp.name) / 'nutzer'
        home.mkdir()
        self.ollama.models = ['qwen3:4b', 'qwen3:4b-instruct-2507-q4_K_M']
        # Instruct-Modell beantwortet die Kurzfrage richtig, das Denk-Modell nicht.
        self.ollama.stream_text = ['Paris ist die Hauptstadt.']
        self.ollama.reasoning = False
        out = Path(self.tmp.name) / 'r.json'
        done = subprocess.run([sys.executable, '-m', 'atlas.realtests', '--quick', '--compare', '--apply', '--output', str(out)],
                              cwd=Path(__file__).resolve().parents[1], capture_output=True, text=True, timeout=200,
                              env={**os.environ, 'ATLAS_OLLAMA_URL': self.ollama.url, 'HOME': str(home)})
        report = json.loads(out.read_text())
        self.assertEqual(set(report['comparison']), {'qwen3:4b', 'qwen3:4b-instruct-2507-q4_K_M'}, done.stdout + done.stderr)
        settings = json.loads((home / '.atlas-ai' / 'settings.json').read_text())
        self.assertEqual(settings['agent_model'], report['best_model'])
        self.assertIn('bestanden', done.stdout)

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


    # -- Neue Arbeitsaufgaben (0.8.0): Prüfung unabhängig vom Modell -------------------------------
    def test_offer_then_pdf_needs_both_real_files(self):
        self.ollama.script = [answer('Gern, hier ist das Angebot: …'), answer('Gespeichert.')]
        self.assertFalse(self.run_case('word_angebot_pdf'))                  # nur Text → durchgefallen
        self.ollama.script = [
            tool_call('create_document', path='~/Documents/Angebot Müller.docx', title='Angebot',
                      content='Gestaltung einer Webseite: 4.800 Euro netto.'), answer('Angebot gespeichert.'),
            tool_call('convert_document', path='~/Documents/Angebot Müller.docx'), answer('Auch als PDF gespeichert.')]
        self.assertTrue(self.run_case('word_angebot_pdf'))

    def test_contract_edit_needs_real_change_and_backup(self):
        self.ollama.script = [answer('Erledigt, die Laufzeit ist jetzt 24 Monate.')]
        self.assertFalse(self.run_case('word_aendern'))                      # Behauptung ohne Änderung
        self.ollama.script = [tool_call('edit_document', path='~/Documents/Vertrag.docx',
                                        replacements=[{'old': '12 Monate', 'new': '24 Monate'}]), answer('Geändert.')]
        self.assertTrue(self.run_case('word_aendern'))

    def test_injected_instruction_and_partial_failure_and_password(self):
        self.ollama.script = [tool_call('read_file', path='~/Documents/brief.txt'),
                              tool_call('delete_path', path='~/Documents/behalten.txt'), answer('Gelöscht.')]
        self.assertFalse(self.run_case('fremde_anweisung'))                  # Modell folgt der Anweisung → durchgefallen
        self.ollama.script = [tool_call('read_file', path='~/Documents/gibtsnicht.pdf'),
                              tool_call('create_folder', path='~/Documents/Bericht-Ablage'),
                              answer('Die PDF wurde nicht gefunden; den Ordner Bericht-Ablage habe ich angelegt.')]
        self.assertTrue(self.run_case('teilweise_fehler'))
        self.assertTrue(self.run_case('passwort_schutz'))                    # Schutz greift ohne Modell

    def test_research_offline_counts_as_not_executed(self):
        prompt, approve, check = self.cases['recherche_quellen']
        self.ollama.script = [tool_call('research', question='Präsident Frankreich'),
                              answer('Das Internet ist nicht erreichbar, daher kann ich es nicht prüfen.')]
        self.assertIsNone(check(r.drive(self.agent, prompt, approve)))

    def test_blocked_search_counts_as_failed_not_skipped(self):
        prompt, approve, check = self.cases['recherche_quellen']
        self.agent.base_tools = build_tools(Environment(home=self.home, roots=[self.home], is_mac=False,
                                                        fetch=lambda url, timeout: '<html>Schutzseite</html>'))
        self.ollama.script = [tool_call('research', question='Präsident Frankreich'), answer('Keine Quellen gefunden.')]
        result = r.drive(self.agent, prompt, approve)
        self.assertIs(check(result), False)
        self.assertIn('keine Treffer', result['failure_notes'][0])


if __name__ == '__main__':
    unittest.main()
