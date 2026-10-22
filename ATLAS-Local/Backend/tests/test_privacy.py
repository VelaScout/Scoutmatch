"""Zugangsdaten werden nie gespeichert – weder als Erinnerung noch als Regel, Erfahrung oder im Journal.

Echt: Erkennung, Agentenablauf bis zur App-Schnittstelle, SQLite. Simuliert: Modellentscheidungen (FakeOllama).
"""
import contextlib
import sqlite3
import tempfile
import threading
import unittest
from pathlib import Path

from atlas import agent as a
from atlas import llm
from atlas.learning import Learning
from atlas.privacy import contains_secret, redact
from atlas.tasks import TaskJournal
from atlas.tools import Environment, build_tools
from fake_ollama import FakeOllama, answer, tool_call

REMEMBER = {'name': 'remember', 'description': 'merken', 'input_schema': {'type': 'object', 'properties': {'content': {'type': 'string'}}}}


class PrivacyTests(unittest.TestCase):
    def test_detects_credentials_but_not_normal_sentences(self):
        for text in ['Mein Passwort ist Sommer2026!', 'Das Passwort für Netflix lautet hund123', 'PIN: 4711', 'Passwort für das Online-Banking: Hund123',
                     'api key = sk-ant-api03-abcdefghijklmnopqrstuv', 'ghp_abcdefghijklmnopqrstuvwxyz0123',
                     'Karte 4111 1111 1111 1111', 'IBAN DE89 3704 0044 0532 0130 00']:
            with self.subTest(text=text):
                self.assertTrue(contains_secret(text))
        for text in ['Ich trainiere montags', 'Mein Passwort-Manager ist 1Password', 'Termin um 14:30',
                     'Rufnummer 030 1234567', 'Die PIN-Eingabe hat geklappt', 'Projekt Atlas läuft bis 2027']:
            with self.subTest(text=text):
                self.assertFalse(contains_secret(text))
        self.assertEqual(redact('Mein Passwort ist Sommer2026!'), 'Mein Passwort ist [entfernt]')

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.ollama = FakeOllama()
        self.addCleanup(self.ollama.close)

    @contextlib.contextmanager
    def connect(self):
        db = sqlite3.connect(self.root / 'atlas.db')
        try:
            with db:
                yield db
        finally:
            db.close()

    def run_agent(self, text, journal=None, learning=None):
        env = Environment(home=self.root, roots=[self.root], is_mac=False)
        agent = a.Agent(llm.Ollama(base=self.ollama.url), build_tools(env), a.Bridge(), journal=journal, learning=learning,
                        limits=a.Limits(max_rounds=4, seconds=20, native_timeout=2))
        request = a.Request(system='ATLAS', history=[{'role': 'user', 'content': text}], native_tools=[REMEMBER])
        events = []
        for event in agent.run(request, threading.Event()):
            events.append(event)
            if event['type'] == 'tool_request':
                agent.bridge.resolve(event['id'], {'content': 'Gespeichert', 'isError': False})
        return events

    def test_direct_remember_of_password_is_refused(self):
        events = self.run_agent('Merk dir: Mein Passwort für Netflix ist Hund123')
        self.assertFalse([e for e in events if e['type'] == 'tool_request'])
        self.assertIn('speichere ich nie', ''.join(e.get('text', '') for e in events))

    def test_model_cannot_store_a_secret_and_nothing_secret_is_logged(self):
        learning, journal = Learning(self.connect), TaskJournal(self.connect)
        self.ollama.script = [tool_call('remember', content='Online-Banking PIN: 4711'), answer('Gemerkt.')]
        events = self.run_agent('Bitte speichere dir meine Online-Banking PIN: 4711 für später', journal, learning)
        self.assertFalse([e for e in events if e['type'] == 'tool_request'])
        with self.connect() as db:
            stored = ' '.join(str(row) for table in ('experiences', 'tasks') for row in db.execute(f'SELECT * FROM {table}'))
        self.assertNotIn('4711', stored)
        self.assertIsNone((learning.learn_correction('Nein, mein Passwort ist Geheim999') or {}).get('rule'))


if __name__ == '__main__':
    unittest.main()
