"""Vollständige Arbeitsabläufe: Folgeaufträge, Abbruch und Wiederaufnahme, keine doppelten Aktionen.

Echt: Agentenablauf, Dateien (Word/PDF), SQLite-Journal über einen simulierten Neustart, Rundreise zur App.
Simuliert: die Entscheidungen des Sprachmodells (FakeOllama) und die App (Antworten auf tool_request).
"""
import contextlib
import sqlite3
import tempfile
import threading
import unittest
from pathlib import Path

from atlas import agent as a
from atlas import llm
from atlas.tasks import TaskJournal
from atlas.tools import Environment, build_tools
from fake_ollama import FakeOllama, answer, tool_call

MAIL = {'name': 'send_email', 'description': 'E-Mail senden', 'input_schema': {
    'type': 'object', 'properties': {'to': {'type': 'string'}, 'subject': {'type': 'string'}, 'body': {'type': 'string'}}}}
REMINDER = {'name': 'create_reminder', 'description': 'Erinnerung anlegen', 'input_schema': {
    'type': 'object', 'properties': {'title': {'type': 'string'}}}}


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.home = self.root / 'home'
        (self.home / 'Documents').mkdir(parents=True)
        self.ollama = FakeOllama()
        self.addCleanup(self.ollama.close)
        self.start()

    @contextlib.contextmanager
    def connect(self):
        db = sqlite3.connect(self.root / 'atlas.db')
        try:
            with db:
                yield db
        finally:
            db.close()

    def start(self):
        """(Neu)start: frische Objekte, gleiche Datenbank, KEIN Gesprächsverlauf aus der App."""
        env = Environment(home=self.home, roots=[self.home], is_mac=False)
        self.journal = TaskJournal(self.connect)
        self.agent = a.Agent(llm.Ollama(base=self.ollama.url), build_tools(env), a.Bridge(), journal=self.journal,
                             limits=a.Limits(max_rounds=6, seconds=30, native_timeout=5))

    def run_agent(self, text, history=None, natives=(), answers=None, stop=None, stop_on=None):
        stop = stop or threading.Event()
        request = a.Request(system='Du bist ATLAS.', history=(history or []) + [{'role': 'user', 'content': text}],
                            native_tools=list(natives))
        events, requests = [], []
        for event in self.agent.run(request, stop):
            events.append(event)
            if event['type'] == 'tool_request':
                requests.append(event)
                if stop_on == event['name']:
                    stop.set()            # Nutzer bricht ab, während die App noch arbeitet
                    continue
                self.agent.bridge.resolve(event['id'], {'content': (answers or {}).get(event['name'], 'OK'), 'isError': False})
        return events, requests

    def prompt(self):
        return self.ollama.chat_requests()[-1]['messages'][0]['content']

    def text(self, events):
        return ''.join(e.get('text', '') for e in events if e['type'] == 'delta')

    def test_save_it_as_pdf_after_restart_uses_the_right_file(self):
        from pypdf import PdfReader
        self.ollama.script = [tool_call('create_document', path='~/Documents/Angebot Müller.docx', title='Angebot',
                                        content='Webseite für 4.800 € netto.'), answer('Das Angebot ist gespeichert.')]
        self.run_agent('Schreibe ein Angebot für Herrn Müller über eine Webseite für 4.800 € als Word-Dokument.')
        word = self.home / 'Documents' / 'Angebot Müller.docx'
        self.assertTrue(word.is_file())
        self.start()                                                     # Neustart, Verlauf weg
        self.ollama.script = [tool_call('convert_document', path=str(word)), answer('Als PDF gespeichert.')]
        events, _ = self.run_agent('Speichere es als PDF')
        prompt = self.prompt()
        self.assertIn(str(word), prompt)                                 # das Modell kennt die gemeinte Datei
        self.assertIn('convert_document', [t['function']['name'] for t in self.ollama.chat_requests()[-1]['tools']])
        pdf = word.with_suffix('.pdf')
        self.assertIn('4.800', ''.join(p.extract_text() for p in PdfReader(str(pdf)).pages))
        self.assertEqual(events[-1]['type'], 'done')

    def test_cancelled_task_resumes_without_repeating_done_steps(self):
        self.ollama.script = [tool_call('create_folder', path='~/Documents/Umzug'),
                              tool_call('create_reminder', title='Umzugskartons bestellen')]
        events, _ = self.run_agent('Lege einen Ordner Umzug in Dokumente an und erinnere mich an die Umzugskartons',
                                   natives=[REMINDER], stop_on='create_reminder')
        self.assertEqual(events[-1]['type'], 'cancelled')
        task = self.journal.unfinished()
        self.assertEqual(task['status'], 'abgebrochen')
        self.start()                                                     # Neustart
        self.ollama.script = [tool_call('create_reminder', title='Umzugskartons bestellen'), answer('Erinnerung angelegt.')]
        events, requests = self.run_agent('Mach weiter', natives=[REMINDER])
        prompt = self.prompt()
        self.assertIn('Bereits erledigt (NICHT wiederholen)', prompt)
        self.assertIn('Umzug', prompt)
        self.assertEqual([r['name'] for r in requests], ['create_reminder'])
        self.assertIsNone(self.journal.unfinished())                     # jetzt abgeschlossen
        self.assertEqual(events[-1]['mode'], 'agent')

    def test_same_email_is_never_sent_twice_silently(self):
        mail = tool_call('send_email', to='anna@example.org', subject='Termin', body='Morgen 10 Uhr passt.')
        self.ollama.script = [mail, answer('E-Mail ist raus.')]
        _, first = self.run_agent('Schreib Anna per Mail, dass morgen 10 Uhr passt.', natives=[MAIL])
        self.assertEqual([r['name'] for r in first], ['send_email'])
        self.start()                                                     # z. B. nach Absturz und Wiederholung
        self.ollama.script = [mail, answer('Erledigt.')]
        events, second = self.run_agent('Schreib Anna per Mail, dass morgen 10 Uhr passt.', natives=[MAIL],
                                        answers={'atlas_confirm': 'denied'})
        self.assertEqual([r['name'] for r in second], ['atlas_confirm'])  # gefragt, nicht erneut gesendet
        self.assertIn('bereits', second[0]['input']['detail'])
        report = next(e for e in events if e['type'] == 'report')
        self.assertTrue(report['declined'])

    def test_different_email_is_not_blocked(self):
        self.ollama.script = [tool_call('send_email', to='anna@example.org', subject='A', body='Eins'), answer('Ok.')]
        self.run_agent('Mail an Anna: Eins', natives=[MAIL])
        self.ollama.script = [tool_call('send_email', to='anna@example.org', subject='B', body='Zwei'), answer('Ok.')]
        _, requests = self.run_agent('Mail an Anna: Zwei', natives=[MAIL])
        self.assertEqual([r['name'] for r in requests], ['send_email'])

    def test_unrelated_success_does_not_resolve_a_failure(self):
        self.ollama.script = [tool_call('read_file', path='~/Documents/fehlt.pdf'),
                              tool_call('read_file', path='~/Documents'), answer('Teilweise.')]
        self.run_agent('Lies fehlt.pdf in Dokumente')
        task = self.journal.recent()[0]
        self.assertEqual(task['status'], 'teilweise')


if __name__ == '__main__':
    unittest.main()
