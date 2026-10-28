"""Optionales Cloud-Modell: aus ohne Aktivierung, Freigabe pro Übertragung, Kosten, Limit, Schlüsselbund.

Echt: offizielles anthropic-SDK, HTTP, Agentenablauf mit Werkzeugen, SQLite-Kostenbuch, `security`-Aufruf
(mit nachgebautem security-Programm). Simuliert: die Anthropic-API (FakeAnthropic), lokales Modell (FakeOllama).
Ein Test mit dem echten Cloud-Modell ist NICHT ausgeführt (kein Schlüssel, keine Kosten ohne Ihre Freigabe).
"""
import contextlib
import json
import os
import sqlite3
import stat
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

try:
    import anthropic
except ImportError:
    anthropic = None

from atlas import agent as a
from atlas import llm
from atlas.cloud import Cloud, Keychain, cost
from atlas.tools import Environment, build_tools
from fake_ollama import FakeOllama
from fake_anthropic import FakeAnthropic, message

KEY = 'sk-ant-api03-testtesttesttesttesttest'


class FakeKeychain:
    def __init__(self, key=None):
        self.key = key

    def available(self):
        return True

    def get(self):
        return self.key

    def set(self, key):
        self.key = key

    def delete(self):
        self.key = None


@unittest.skipUnless(anthropic, 'anthropic-SDK fehlt')
class CloudTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        (self.root / 'home' / 'Documents').mkdir(parents=True)
        self.api = FakeAnthropic()
        self.addCleanup(self.api.close)
        self.ollama = FakeOllama()
        self.addCleanup(self.ollama.close)
        self.ollama.stream_text = ['Lokale Antwort.']
        self.stored = {}
        self.cloud = Cloud(self.connect, lambda: self.stored, lambda v: self.stored.update(v), FakeKeychain(KEY),
                           client_factory=lambda: anthropic.Anthropic(api_key=KEY, base_url=self.api.url, max_retries=0))
        env = Environment(home=self.root / 'home', roots=[self.root / 'home'], is_mac=False)
        self.agent = a.Agent(llm.Ollama(base=self.ollama.url), build_tools(env), a.Bridge(),
                             limits=a.Limits(max_rounds=4, seconds=30, native_timeout=5))
        self.agent.cloud = self.cloud

    @contextlib.contextmanager
    def connect(self):
        db = sqlite3.connect(self.root / 'atlas.db')
        try:
            with db:
                yield db
        finally:
            db.close()

    def ask(self, text, approve=True):
        request = a.Request(system='Du bist ATLAS.', history=[{'role': 'user', 'content': text}], native_tools=[])
        events, confirms = [], []
        for event in self.agent.run(request, threading.Event()):
            events.append(event)
            if event['type'] == 'tool_request':
                confirms.append(event['input'])
                self.agent.bridge.resolve(event['id'], {'content': 'approved' if approve else 'denied', 'isError': False})
        return ''.join(e.get('text', '') for e in events if e['type'] == 'delta'), confirms, events

    def test_off_by_default_nothing_leaves_the_mac(self):
        text, confirms, _ = self.ask('Cloud: Erkläre mir Quantencomputer')
        self.assertIn('Cloud nicht verfügbar (ausgeschaltet)', text)
        self.assertIn('Lokale Antwort.', text)
        self.assertEqual(self.api.requests, [])
        self.assertEqual(confirms, [])

    def test_declined_transfer_sends_nothing(self):
        self.cloud.update(enabled=True)
        text, confirms, _ = self.ask('Cloud: Erkläre mir Quantencomputer', approve=False)
        self.assertIn('An Anthropic (claude-opus-5-5) gehen', confirms[0]['detail'])
        self.assertIn('US-$', confirms[0]['detail'])
        self.assertIn('Nichts wurde in die Cloud gesendet', text)
        self.assertEqual(self.api.requests, [])

    def test_cloud_task_with_tools_thinking_replay_and_cost(self):
        self.cloud.update(enabled=True)
        thinking = {'type': 'thinking', 'thinking': '', 'signature': 'sig-abc'}
        self.api.script = [
            message([thinking, {'type': 'tool_use', 'id': 'toolu_1', 'name': 'create_folder',
                                'input': {'path': '~/Documents/Projekt Cloud'}}], stop='tool_use'),
            message([{'type': 'text', 'text': 'Ordner angelegt.'}], input_tokens=1500, output_tokens=100)]
        text, confirms, events = self.ask('Mit Claude: Lege in Dokumente einen Ordner Projekt Cloud an')
        self.assertTrue((self.root / 'home' / 'Documents' / 'Projekt Cloud').is_dir())
        first, second = (r['body'] for r in self.api.requests)
        self.assertEqual(first['model'], 'claude-opus-5-5')
        self.assertEqual(first['fallbacks'], 'default')
        self.assertIn('server-side-fallback-2026-07-01', self.api.requests[0]['headers'].get('anthropic-beta', ''))
        self.assertNotIn('temperature', first)
        self.assertEqual(first['messages'][-1]['content'], 'Lege in Dokumente einen Ordner Projekt Cloud an')  # ohne Präfix
        replay = second['messages'][-2]
        self.assertEqual(replay['content'][0], thinking)                               # Denkblock unverändert zurück
        self.assertEqual(second['messages'][-1]['content'][0]['tool_use_id'], 'toolu_1')
        expected = cost('claude-opus-5-5', 2500, 300)
        self.assertAlmostEqual(self.cloud.spent_this_month(), expected)
        self.assertIn('2 Anfrage(n), 2500 Token gesendet, 300 Token empfangen', text)
        done = events[-1]
        self.assertAlmostEqual(done['cloud']['cost_usd'], round(expected, 5))
        self.assertEqual(len(confirms), 1)

    def test_fallback_hops_are_priced_per_model(self):
        self.cloud.update(enabled=True, always_allow=True)
        self.api.script = [message([{'type': 'text', 'text': 'Antwort.'}], iterations=[
            {'type': 'message', 'model': 'claude-opus-5-5', 'input_tokens': 800, 'output_tokens': 10,
             'cache_creation_input_tokens': 0, 'cache_read_input_tokens': 0},
            {'type': 'fallback_message', 'model': 'claude-opus-5', 'input_tokens': 800, 'output_tokens': 300,
             'cache_creation_input_tokens': 0, 'cache_read_input_tokens': 0}])]
        _, confirms, _ = self.ask('Cloud: Frage')
        self.assertEqual(confirms, [])                                                   # Dauerfreigabe
        self.assertAlmostEqual(self.cloud.spent_this_month(), cost('claude-opus-5-5', 800, 10) + cost('claude-opus-5', 800, 300))

    def test_monthly_limit_stops_transfers(self):
        self.cloud.update(enabled=True, monthly_limit_usd=0.01)
        self.cloud.record('claude-opus-5-5', 10_000, 0)                                  # 0,04 US-$ verbraucht
        text, _, _ = self.ask('Cloud: Frage')
        self.assertIn('Monatslimit erreicht', text)
        self.assertEqual(self.api.requests, [])

    def test_settings_are_validated(self):
        for bad in [{'model': 'gpt-5'}, {'monthly_limit_usd': -1}, {'enabled': 'ja'}, {'temperature': 1}]:
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                self.cloud.update(**bad)


class KeychainTests(unittest.TestCase):
    def test_key_goes_via_stdin_never_argv_and_is_validated(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            log = folder / 'aufrufe.txt'
            store = folder / 'store.txt'
            script = folder / 'security'
            script.write_text(f'''#!/bin/sh
echo "ARGS $*" >> {log}
if [ "$1" = "-i" ]; then cat >> {log}; sed -n 's/.*-w "\\(.*\\)"/\\1/p' {log} | tail -1 > {store}; exit 0; fi
if [ "$1" = "find-generic-password" ]; then cat {store} 2>/dev/null || exit 44; fi
''')
            script.chmod(script.stat().st_mode | stat.S_IEXEC)
            with mock.patch.dict(os.environ, {'PATH': f'{folder}:{os.environ["PATH"]}'}):
                chain = Keychain()
                chain.set(KEY)
                self.assertEqual(chain.get(), KEY)
                args = [line for line in log.read_text().splitlines() if line.startswith('ARGS')]
                self.assertFalse(any(KEY in line for line in args))                       # nie in der Prozessliste
                with self.assertRaises(Exception):
                    chain.set('abc"; delete-keychain login.keychain; "')
                self.assertNotIn('delete-keychain', log.read_text())


if __name__ == '__main__':
    unittest.main()
