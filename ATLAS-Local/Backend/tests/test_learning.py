"""Erfahrungslernen, Ergebnisbewertung und Lernen aus Korrekturen.

Echt: Datenbank (SQLite, auch über einen simulierten Neustart), Dateiwerkzeuge, Agentenablauf.
Simuliert: das Sprachmodell (FakeOllama gibt Werkzeugaufrufe vor).
"""
import contextlib
import json
import sqlite3
import tempfile
import threading
import unittest
from pathlib import Path

from atlas import agent as a
from atlas import llm
from atlas.learning import Learning, error_class, task_type
from atlas.tools import Environment, build_tools
from fake_ollama import FakeOllama, answer, tool_call


def action(tool, ok=True, verified=True, output='ok', declined=False):
    return a.Action(tool, tool, tool, ok, verified, output, declined)


class LearningTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.db_path = Path(self.tmp.name) / 'atlas.db'
        self.home = Path(self.tmp.name).resolve() / 'home'
        for name in ('Desktop', 'Documents', 'Downloads'):
            (self.home / name).mkdir(parents=True)
        self.ollama = FakeOllama()
        self.addCleanup(self.ollama.close)
        self.start_atlas()

    @contextlib.contextmanager
    def connect(self):
        db = sqlite3.connect(self.db_path)
        try:
            with db:
                yield db
        finally:
            db.close()

    def start_atlas(self):
        """(Neu)start: frische Objekte, gleiche Datenbank – wie nach einem Neustart des Macs."""
        self.learning = Learning(self.connect)
        env = Environment(home=self.home, roots=[self.home], is_mac=False)
        self.agent = a.Agent(llm.Ollama(base=self.ollama.url), build_tools(env), a.Bridge(),
                             limits=a.Limits(max_rounds=6, seconds=30, native_timeout=2), learning=self.learning)

    def ask(self, text):
        request = a.Request(system='Du bist ATLAS.', history=[{'role': 'user', 'content': text}])
        return list(self.agent.run(request, threading.Event()))

    def system_prompt(self, index=-1):
        return self.ollama.chat_requests()[index]['messages'][0]['content']

    # -- Bewertung und Reflexion -----------------------------------------------------------
    def test_outcome_evaluation(self):
        evaluate = Learning.evaluate
        self.assertEqual(evaluate([action('write_file')], True), ('erfolg', True))
        self.assertEqual(evaluate([action('write_file', verified=False)], True), ('erfolg', False))
        self.assertEqual(evaluate([action('read_file', ok=False, output='Nicht gefunden')], True), ('fehlgeschlagen', False))
        self.assertEqual(evaluate([action('run_tests', ok=False), action('run_tests')], True), ('erfolg', True))
        self.assertEqual(evaluate([action('create_folder'), action('write_file', ok=False)], True), ('teilweise', False))
        self.assertEqual(evaluate([action('create_folder')], False), ('teilweise', False))
        self.assertEqual(evaluate([], True), ('ohne_aktion', False))
        self.assertEqual(evaluate([action('x')], True, cancelled=True), ('abgebrochen', False))

    def test_reflection_names_what_worked_instead(self):
        lesson = Learning.reflect('Excel erstellen', [
            action('write_file', ok=False, output='Datei existiert bereits'), action('create_spreadsheet')], 'erfolg', 3.0)
        self.assertIn('Statt write_file', lesson)
        self.assertIn('hat create_spreadsheet funktioniert', lesson)
        self.assertIn('Bewährter Ablauf', lesson)
        self.assertEqual(error_class('Pfad außerhalb der freigegebenen Ordner'), 'pfad')
        self.assertEqual(task_type('Sortiere meine Downloads', []), 'sortieren')
        self.assertEqual(task_type('irgendwas', ['run_tests']), 'code')

    # -- Erfahrungsgedächtnis im Agenten ------------------------------------------------------
    def test_verified_success_is_reused_for_similar_task(self):
        self.ollama.script = [tool_call('create_folder', path='~/Documents/Rechnungen 2026'), answer('Ordner angelegt.')]
        self.ask('Erstelle in Dokumente einen Ordner Rechnungen 2026')
        rows = self.learning.list('experiences')
        self.assertEqual((rows[0]['outcome'], rows[0]['verified'], rows[0]['task_type']), ('erfolg', 1, 'dateien'))
        self.assertIn('Bewährter Ablauf: create_folder', rows[0]['lesson'])
        self.ollama.script = [tool_call('create_folder', path='~/Documents/Rechnungen 2027'), answer('Ordner angelegt.')]
        self.ask('Erstelle in Dokumente einen Ordner Rechnungen 2027')
        prompt = self.system_prompt()
        self.assertIn('Bewährt bei ähnlichen Aufgaben', prompt)
        self.assertIn('Rechnungen 2026', prompt)

    def test_failure_becomes_warning_not_proven(self):
        self.ollama.script = [tool_call('read_file', path='~/Documents/fehlt.pdf'), answer('Ging nicht.')]
        self.ask('Fasse die PDF fehlt.pdf in Dokumente zusammen')
        self.ollama.script = [answer('Moment.')]
        self.ask('Fasse die PDF bericht.pdf in Dokumente zusammen')
        prompt = self.system_prompt()
        self.assertIn('Frühere Probleme', prompt)
        self.assertNotIn('Bewährt bei ähnlichen', prompt)

    def test_unverified_results_are_not_treated_as_proven(self):
        exp = self.learning.record('Öffne Safari', 'agent', 'm', [action('open_app', verified=False)], True, 1.0)
        self.assertEqual(self.learning.list('experiences')[0]['verified'], 0)
        self.assertNotIn('Bewährt', self.learning.context_for('Öffne Safari bitte'))
        self.learning.confirm_experience(exp, True)
        self.assertIn('Bewährt', self.learning.context_for('Öffne Safari bitte'))

    # -- Korrekturen ------------------------------------------------------------------------------
    def test_correction_is_learned_and_survives_restart(self):
        self.ollama.script = [tool_call('write_file', path='~/Desktop/notiz.txt', content='Hallo'), answer('Gespeichert.')]
        self.ask('Speichere eine Notiz notiz.txt mit dem Text Hallo')
        self.ollama.script = [tool_call('write_file', path='~/Documents/notiz.txt', content='Hallo'),
                              answer('Erledigt, jetzt in Dokumente.')]
        events = self.ask('Atlas, das war nicht richtig. Du solltest die Datei in Dokumente speichern.')
        self.assertTrue(any(e['type'] == 'learned' for e in events))
        self.assertTrue((self.home / 'Documents' / 'notiz.txt').is_file())          # sofort richtig ausgeführt
        rule = self.learning.list('rules')[0]
        self.assertEqual(rule['text'], 'Du solltest die Datei in Dokumente speichern')
        self.assertEqual(rule['scope'], 'aehnliche_aufgaben')                      # einmalig formuliert
        first = self.learning.list('experiences')[-1]
        self.assertEqual((first['outcome'], first['verified'], first['corrected']), ('korrigiert', 0, 1))

        self.start_atlas()                                                          # Neustart
        self.ollama.script = [tool_call('write_file', path='~/Documents/einkauf.txt', content='Milch'), answer('Gespeichert.')]
        self.ask('Speichere eine Datei einkauf.txt mit Milch')
        self.assertIn('Du solltest die Datei in Dokumente speichern', self.system_prompt())
        self.ollama.stream_text = ['Mir geht es gut.']
        self.ask('Wie geht es dir heute?')                                          # anderes Thema → Regel nicht nötig
        self.assertNotIn('Dokumente speichern', self.system_prompt())

    def test_durable_preference_applies_everywhere(self):
        self.ollama.script = [answer('Verstanden.')]
        self.ask('Nein, antworte ab jetzt immer auf Englisch und kurz.')
        rule = self.learning.list('rules')[0]
        self.assertEqual(rule['scope'], 'dauerhaft')
        self.start_atlas()
        self.ollama.stream_text = ['Fine.']
        self.ask('Wie geht es dir heute?')
        self.assertIn('antworte ab jetzt immer auf Englisch', self.system_prompt())

    def test_same_correction_updates_instead_of_duplicating(self):
        self.learning.learn_correction('Nein, speichere ab jetzt immer in Dokumente.')
        self.learning.learn_correction('Nein, speichere ab jetzt immer in Dokumente!')
        self.assertEqual(len(self.learning.list('rules')), 1)

    def test_rules_can_be_edited_disabled_and_deleted(self):
        result = self.learning.learn_correction('Falsch. Nenn mich ab jetzt immer Herr Velasco.')
        rule_id = result['rule']
        self.assertTrue(self.learning.edit_rule(rule_id, text='Anrede: immer „Herr Velasco“'))
        self.assertIn('Herr Velasco', self.learning.context_for('Hallo', rules_only=True))
        self.learning.edit_rule(rule_id, active=False)
        self.assertEqual(self.learning.context_for('Hallo', rules_only=True), '')
        self.assertTrue(self.learning.delete('rules', rule_id))
        self.assertEqual(self.learning.list('rules'), [])
        with self.assertRaises(ValueError):
            self.learning.list('sqlite_master')

    # -- Kennzahlen und Export ---------------------------------------------------------------------
    def test_metrics_reflect_reality(self):
        record = self.learning.record
        record('Ordner A', 'agent', 'm', [action('create_folder')], True, 2.0)
        record('PDF B', 'agent', 'm', [action('read_file', ok=False, output='Nicht gefunden')], True, 4.0)
        record('PDF C', 'agent', 'm', [action('read_file', ok=False, output='Nicht gefunden')], True, 6.0)
        record('Excel D', 'plan', 'm', [action('create_spreadsheet'), action('read_file')], True, 8.0)
        values = self.learning.metrics()
        self.assertEqual(values['tasks'], 4)
        self.assertEqual(values['success_rate'], 0.5)
        self.assertEqual(values['tool_reliability'], 0.6)
        self.assertEqual(values['avg_duration_s'], 5.0)
        self.assertEqual(values['repeated_errors'], 2)
        self.assertEqual(values['top_errors'][0], {'tool': 'read_file', 'class': 'pfad', 'count': 2})
        self.learning.snapshot()
        self.assertEqual(self.learning.history()[-1]['success_rate'], 0.5)

    def test_training_export_contains_only_confirmed_examples(self):
        self.learning.record('Ordner A', 'agent', 'm', [action('create_folder')], True, 2.0)
        self.learning.record('Ordner B', 'agent', 'm', [action('create_folder', verified=False)], True, 2.0)
        self.learning.record('PDF', 'agent', 'm', [action('read_file', ok=False)], True, 2.0)
        data = self.learning.export_training_data()
        self.assertEqual([d['messages'][0]['content'] for d in data], ['Ordner A'])
        json.dumps(data)


if __name__ == '__main__':
    unittest.main()
