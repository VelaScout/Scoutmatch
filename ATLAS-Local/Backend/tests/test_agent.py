"""Ende-zu-Ende-Tests des Agenten über den echten HTTP-Server.

Echt: Server, NDJSON-Streaming, Rundreise zur „App“ (Testclient antwortet wie die
native App), Dateiwerkzeuge in einem temporären Home-Ordner, Gedächtnis-Datenbank.
Simuliert: das Sprachmodell (FakeOllama gibt Werkzeugaufrufe und Antworten vor).
"""
import http.client
import json
import tempfile
import threading
import time
import unittest
from pathlib import Path

from atlas import agent as a
from atlas import llm
from atlas import server as s
from atlas import tools as t
from atlas.memory import MemoryIndex
from fake_ollama import FakeOllama, answer, tool_call
from test_tools import FakeRunner

NATIVE_TOOLS = [
    {'name': 'get_calendar_events', 'description': 'Termine lesen', 'input_schema': {'type': 'object', 'properties': {'days': {'type': 'integer'}}}},
    {'name': 'remember', 'description': 'Merken', 'input_schema': {'type': 'object', 'properties': {'content': {'type': 'string'}}}},
    {'name': 'list_memories', 'description': 'Erinnerungen', 'input_schema': {'type': 'object', 'properties': {}}},
    {'name': 'forget', 'description': 'Vergessen', 'input_schema': {'type': 'object', 'properties': {'content': {'type': 'string'}}}},
]


class AgentServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        s.DATA = Path(cls.tmp.name) / 'data'
        s.DB = s.DATA / 'atlas.db'
        cls.http = s.ThreadingHTTPServer(('127.0.0.1', 0), s.Handler)
        cls.thread = threading.Thread(target=cls.http.serve_forever, daemon=True)
        cls.thread.start()
        cls.port = cls.http.server_port

    @classmethod
    def tearDownClass(cls):
        cls.http.shutdown()
        cls.http.server_close()
        cls.thread.join()
        cls.tmp.cleanup()

    def setUp(self):
        self.ollama = FakeOllama()
        self.addCleanup(self.ollama.close)
        self.home_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.home_dir.cleanup)
        self.home = Path(self.home_dir.name).resolve()
        for name in ('Desktop', 'Documents', 'Downloads'):
            (self.home / name).mkdir()
        client = llm.Ollama(base=self.ollama.url)
        env = t.Environment(home=self.home, roots=[self.home], runner=FakeRunner(), fetch=lambda u, timeout: '', is_mac=False)
        self.agent = a.Agent(client, t.build_tools(env), s.BRIDGE, MemoryIndex(s.database, client.embed),
                             limits=a.Limits(max_rounds=6, seconds=20, native_timeout=5))
        s._AGENT = self.agent
        self.native_answers = {}
        self.native_seen = []

    def tearDown(self):
        s._AGENT = None

    # -- Testclient, der sich wie die native App verhält ------------------------------------
    def body(self, text, history=None, memories=None):
        rows = (history or []) + [{'role': 'user', 'content': '[Kontext: Dienstag, 21. Oktober 2026, 18:00 Uhr]\n' + text}]
        return {'system': 'Du bist A.T.L.A.S., lokal auf dem Mac.', 'history': rows, 'memories': memories or [],
                'tools': NATIVE_TOOLS, 'model': 'qwen3:4b', 'request_id': 'r-' + str(time.monotonic())}

    def run_agent(self, payload, on_line=None):
        connection = http.client.HTTPConnection('127.0.0.1', self.port, timeout=30)
        data = json.dumps(payload).encode()
        connection.request('POST', '/api/native/agent/stream', body=data, headers={
            'X-Atlas-Token': s.TOKEN, 'Content-Type': 'application/json', 'Content-Length': str(len(data))})
        response = connection.getresponse()
        if response.status != 200:
            body = response.read()
            connection.close()
            return response.status, [json.loads(body)]
        events = []
        while True:
            line = response.readline()
            if not line:
                break
            event = json.loads(line)
            events.append(event)
            if event['type'] == 'tool_request':
                self.native_seen.append(event)
                handler = self.native_answers.get(event['name'], {'content': 'ok'})
                reply = handler(event) if callable(handler) else handler
                if reply is not None:
                    self.post('/api/native/agent/result', {'id': event['id'], **reply})
            if on_line:
                on_line(event)
        connection.close()
        return 200, events

    def post(self, path, obj):
        connection = http.client.HTTPConnection('127.0.0.1', self.port, timeout=10)
        data = json.dumps(obj).encode()
        connection.request('POST', path, body=data, headers={'X-Atlas-Token': s.TOKEN, 'Content-Length': str(len(data))})
        response = connection.getresponse()
        result = response.status, response.read()
        connection.close()
        return result

    @staticmethod
    def text(events):
        return ''.join(e.get('text', '') for e in events if e['type'] == 'delta')

    # -- Tests -----------------------------------------------------------------------------
    def test_session_advertises_agent_protocol(self):
        connection = http.client.HTTPConnection('127.0.0.1', self.port, timeout=5)
        connection.request('GET', '/api/native/session')
        data = json.loads(connection.getresponse().read())
        connection.close()
        self.assertEqual(data['protocol'], 1)
        self.assertEqual(data['agent'], 2)
        self.assertEqual(data['version'], s.VERSION)

    def test_simple_calculation_needs_no_model(self):
        status, events = self.run_agent(self.body('Was ist 17 mal 23?'))
        self.assertEqual(status, 200)
        self.assertEqual(self.text(events), '391.')
        self.assertEqual(self.ollama.chat_requests(), [])

    def test_small_talk_streams_without_tools(self):
        self.ollama.stream_text = ['Mir geht es ', 'gut, danke.']
        _, events = self.run_agent(self.body('Wie geht es dir?'))
        self.assertEqual(self.text(events), 'Mir geht es gut, danke.')
        request = self.ollama.chat_requests()[0]
        self.assertTrue(request['stream'])
        self.assertNotIn('tools', request)
        self.assertEqual(request['model'], 'qwen3:4b')
        self.assertEqual(events[-1]['mode'], 'chat')

    def test_agent_creates_folder_and_document_for_real(self):
        self.ollama.script = [
            tool_call('create_folder', path='~/Desktop/Ideen'),
            tool_call('write_file', path='~/Desktop/Ideen/Plan.txt', content='1. Atlas testen'),
            answer('Ich habe den Ordner Ideen angelegt und dort Plan.txt gespeichert.'),
        ]
        _, events = self.run_agent(self.body('Erstelle auf dem Schreibtisch einen Ordner Ideen und speichere dort ein Dokument Plan.txt'))
        self.assertEqual((self.home / 'Desktop' / 'Ideen' / 'Plan.txt').read_text(), '1. Atlas testen')
        steps = [(e['tool'], e['status']) for e in events if e['type'] == 'step']
        self.assertIn(('create_folder', 'erledigt'), steps)
        self.assertIn(('write_file', 'erledigt'), steps)
        report = next(e for e in events if e['type'] == 'report')
        self.assertEqual(len(report['done']), 2)
        self.assertEqual(report['failed'], [])
        # Agent nutzt das stärkere installierte Modell und sieht die Dateiwerkzeuge.
        first = self.ollama.chat_requests()[0]
        self.assertEqual(first['model'], 'qwen3:8b')
        names = {tool['function']['name'] for tool in first['tools']}
        self.assertTrue({'create_folder', 'write_file'} <= names)
        # Werkzeugergebnis geht mit Prüfvermerk zurück an das Modell.
        tool_message = [m for m in self.ollama.chat_requests()[1]['messages'] if m['role'] == 'tool'][0]
        self.assertTrue(json.loads(tool_message['content'])['verified'])

    def test_delete_requires_confirmation_and_respects_no(self):
        file = self.home / 'Documents' / 'alt.txt'
        file.write_text('x')
        self.native_answers['atlas_confirm'] = {'content': 'denied'}
        self.ollama.script = [tool_call('delete_path', path='~/Documents/alt.txt'), answer('Okay, ich lasse die Datei.')]
        _, events = self.run_agent(self.body('Lösche die Datei alt.txt in Dokumente'))
        self.assertTrue(file.exists())
        confirm = [e for e in self.native_seen if e['name'] == 'atlas_confirm'][0]
        self.assertIn('alt.txt', confirm['input']['detail'])
        self.assertIn(('delete_path', 'abgelehnt'), [(e['tool'], e['status']) for e in events if e['type'] == 'step'])
        report = next(e for e in events if e['type'] == 'report')
        self.assertEqual(report['failed'], [])
        self.assertEqual(len(report['declined']), 1)
        self.assertNotIn('Fehlgeschlagen', self.text(events))

    def test_delete_after_yes_moves_to_trash(self):
        file = self.home / 'Documents' / 'alt.txt'
        file.write_text('x')
        self.native_answers['atlas_confirm'] = {'content': 'approved'}
        self.ollama.script = [tool_call('delete_path', path='~/Documents/alt.txt'), answer('Datei liegt im Papierkorb.')]
        self.run_agent(self.body('Lösche die Datei alt.txt in Dokumente'))
        self.assertFalse(file.exists())
        self.assertEqual(len(list((self.home / '.Trash').iterdir())), 1)

    def test_dangerous_command_is_blocked_without_asking(self):
        self.ollama.script = [tool_call('run_command', command='sudo rm -rf /', folder='~'), answer('Das mache ich nicht.')]
        _, events = self.run_agent(self.body('Führe im Terminal sudo rm -rf / aus'))
        self.assertEqual([e for e in self.native_seen if e['name'] == 'atlas_confirm'], [])
        self.assertIn(('run_command', 'gesperrt'), [(e['tool'], e['status']) for e in events if e['type'] == 'step'])

    def test_native_calendar_round_trip(self):
        self.native_answers['get_calendar_events'] = {'content': 'Morgen 9:00 Zahnarzt'}
        self.ollama.script = [tool_call('get_calendar_events', days=2), answer('Morgen um neun hast du den Zahnarzt.')]
        _, events = self.run_agent(self.body('Zeig mir meine nächsten Termine im Kalender'))
        self.assertEqual(self.native_seen[0]['name'], 'get_calendar_events')
        self.assertEqual(self.native_seen[0]['input'], {'days': 2})
        tool_message = [m for m in self.ollama.chat_requests()[1]['messages'] if m['role'] == 'tool'][0]
        self.assertIn('Zahnarzt', tool_message['content'])
        self.assertIn('Zahnarzt', self.text(events))

    def test_false_success_claim_is_corrected(self):
        self.ollama.script = [tool_call('read_file', path='~/Documents/fehlt.pdf'),
                              answer('Ich habe die PDF zusammengefasst und gespeichert.')]
        _, events = self.run_agent(self.body('Lies die PDF fehlt.pdf in Dokumente und fasse sie zusammen'))
        text = self.text(events)
        self.assertIn('Keine der Aktionen wurde bestätigt', text)
        self.assertIn('Fehlgeschlagen', text)

    def test_repeated_failure_is_not_retried_forever(self):
        self.ollama.script = [tool_call('read_file', path='~/x.txt')] * 6
        _, events = self.run_agent(self.body('Lies die Datei x.txt'))
        tool_steps = [e for e in events if e['type'] == 'step' and e['tool'] == 'read_file' and e['status'] != 'läuft']
        self.assertEqual(len(tool_steps), 2)
        self.assertIn('nicht ganz fertig', self.text(events))
        last_messages = self.ollama.chat_requests()[-1]['messages']
        self.assertIn('schon zweimal fehlgeschlagen', last_messages[-1]['content'])

    def test_plan_mode_reports_open_steps_when_stopped_early(self):
        self.agent.limits.max_rounds = 2
        self.ollama.script = [
            answer(json.dumps({'steps': ['Projekt ansehen', 'Tests ausführen', 'Fehler beheben', 'Bericht schreiben']})),
            tool_call('list_directory', path='~/Documents'),
            tool_call('list_directory', path='~/Desktop'),
        ]
        _, events = self.run_agent(self.body('Aufgabe: Untersuche mein Projekt auf Fehler, behebe sie und teste alles'))
        plan = next(e for e in events if e['type'] == 'plan')
        self.assertEqual(len(plan['steps']), 4)
        report = next(e for e in events if e['type'] == 'report')
        self.assertEqual(report['open'], plan['steps'])
        self.assertEqual(len(report['done']), 2)
        self.assertIn('Offen:', self.text(events))

    def test_cancel_while_waiting_for_app(self):
        self.native_answers['get_calendar_events'] = lambda event: None  # App antwortet nicht
        self.ollama.script = [tool_call('get_calendar_events')]
        payload = self.body('Welche Termine habe ich im Kalender?')

        def cancel(event):
            if event['type'] == 'tool_request':
                self.post('/api/chat/cancel', {'request_id': payload['request_id']})
        started = time.monotonic()
        _, events = self.run_agent(payload, on_line=cancel)
        self.assertEqual(events[-1]['type'], 'cancelled')
        self.assertLess(time.monotonic() - started, 4)

    def test_long_model_call_sends_heartbeats(self):
        self.agent.limits.heartbeat = 0.2
        self.ollama.delay = 0.7
        self.ollama.script = [tool_call('list_directory', path='~'), answer('Hier ist die Liste.')]
        _, events = self.run_agent(self.body('Liste die Dateien in meinem Ordner auf'))
        self.assertGreaterEqual(sum(e['type'] == 'ping' for e in events), 4)
        self.assertEqual(events[-1]['type'], 'done')

    def test_busy_returns_409(self):
        self.ollama.delay = 1.0
        self.ollama.script = [tool_call('list_directory', path='~'), answer('ok')]
        results = {}
        worker = threading.Thread(target=lambda: results.update(first=self.run_agent(self.body('Liste meine Dateien im Ordner'))))
        worker.start()
        time.sleep(0.3)
        status, _ = self.run_agent(self.body('Liste meine Dateien im Ordner'))
        worker.join()
        self.assertEqual(status, 409)
        self.assertEqual(results['first'][0], 200)

    def test_invalid_requests(self):
        good = self.body('Hallo')
        for change in ({'history': []}, {'history': [{'role': 'system', 'content': 'x'}]},
                       {'model': 'gpt-oss:120b-cloud'}, {'memories': 'kein array'}, {'tools': [{'x': 1}]},
                       {'system': 'S' * 8001}):
            with self.subTest(change=str(change)[:60]):
                status, _ = self.run_agent({**good, **change})
                self.assertEqual(status, 400)
        self.assertEqual(self.post('/api/native/agent/result', {'id': 'unbekannt', 'content': 'x'})[0], 404)

    def test_result_requires_token(self):
        connection = http.client.HTTPConnection('127.0.0.1', self.port, timeout=5)
        connection.request('POST', '/api/native/agent/result', body=b'{}', headers={'Content-Length': '2'})
        self.assertEqual(connection.getresponse().status, 403)
        connection.close()

    def test_text_tool_calls_from_small_models_are_understood(self):
        self.ollama.script = [answer('<tool_call>{"name": "create_folder", "arguments": {"path": "~/Documents/Neu"}}</tool_call>'),
                              answer('Ordner angelegt.')]
        self.run_agent(self.body('Erstelle einen Ordner Neu in Dokumente'))
        self.assertTrue((self.home / 'Documents' / 'Neu').is_dir())

    def test_relevant_memories_reach_the_model(self):
        memories = [f'[Sonstiges] Notiz {i} über Gartenarbeit' for i in range(20)] + [
            '[Vorliebe] Trinkt morgens am liebsten Cappuccino', '[Arbeit] Projekt Atlas läuft auf dem Mac']
        self.ollama.models.append('nomic-embed-text')
        self.ollama.stream_text = ['Einen Cappuccino.']
        self.run_agent(self.body('Welchen Kaffee mag ich?', memories=memories))
        system = self.ollama.chat_requests()[0]['messages'][0]['content']
        self.assertIn('Cappuccino', system)
        self.assertNotIn('Notiz 19', system)
        self.assertGreaterEqual(self.ollama.embed_calls, 1)


    def test_english_question_gets_english_instruction(self):
        self.ollama.stream_text = ['Paris is the capital.']
        self.run_agent(self.body('What is the capital of France and why is it famous?'))
        system = self.ollama.chat_requests()[0]['messages'][0]['content']
        self.assertIn('Answer in natural English', system)

    def test_correction_offers_remember_and_is_learned(self):
        self.native_answers['remember'] = {'content': 'Gemerkt.'}
        self.ollama.script = [tool_call('remember', content='[Vorliebe] Antworten immer kurz halten'),
                              answer('Alles klar, ab jetzt kurz.')]
        _, events = self.run_agent(self.body('Nein, bitte antworte ab jetzt immer kurz.'))
        first = self.ollama.chat_requests()[0]
        names = {tool['function']['name'] for tool in first['tools']}
        self.assertIn('remember', names)
        self.assertLess(len(names), 6)
        self.assertIn('korrigiert dich', first['messages'][0]['content'])
        self.assertEqual(self.native_seen[0]['name'], 'remember')
        self.assertIn('kurz', self.text(events))


    def test_duplicate_memory_is_not_stored_twice(self):
        self.ollama.script = [tool_call('remember', content='[Vorliebe] Trinkt morgens Cappuccino.'),
                              answer('Weiß ich schon.')]
        self.run_agent(self.body('Merk dir bitte, dass ich morgens Cappuccino trinke',
                                 memories=['[Vorliebe] Trinkt morgens Cappuccino']))
        self.assertEqual([e for e in self.native_seen if e['name'] == 'remember'], [])
        # „Merk dir …“ ist ein Schnellweg ohne Modell – auch dort greift die Duplikatprüfung.
        _, events = self.run_agent(self.body('Merk dir: Trinkt morgens Cappuccino',
                                             memories=['[Vorliebe] Trinkt morgens Cappuccino']))
        self.assertIn('Das weiß ich schon', self.text(events))
        self.assertEqual([e for e in self.native_seen if e['name'] == 'remember'], [])

    def test_duplicate_from_model_is_reported_back(self):
        self.ollama.script = [tool_call('remember', content='[Vorliebe] Trinkt morgens Cappuccino.'), answer('Weiß ich schon.')]
        self.run_agent(self.body('Ich trinke übrigens morgens immer Cappuccino, merk dir das',
                                 memories=['[Vorliebe] Trinkt morgens Cappuccino']))
        self.assertEqual([e for e in self.native_seen if e['name'] == 'remember'], [])
        tool_message = [m for m in self.ollama.chat_requests()[1]['messages'] if m['role'] == 'tool'][0]
        self.assertIn('bereits gespeichert', tool_message['content'])

    def test_similar_memory_suggests_update(self):
        self.native_answers['remember'] = {'content': 'Gemerkt.'}
        self.ollama.script = [tool_call('remember', content='[Persönlich] Wohnt jetzt in Hamburg, Altona'),
                              tool_call('forget', content='Wohnt in Berlin'), answer('Notiert: Hamburg.')]
        self.native_answers['forget'] = {'content': 'Vergessen.'}
        self.ollama.models.append('nomic-embed-text')
        self.run_agent(self.body('Merk dir: Ich wohne jetzt in Hamburg', memories=['[Persönlich] Wohnt in Berlin, Altona']))
        self.assertEqual([e['name'] for e in self.native_seen], ['remember', 'forget'])
        tool_message = [m for m in self.ollama.chat_requests()[1]['messages'] if m['role'] == 'tool'][0]
        self.assertIn('Ähnliche ältere Erinnerung', tool_message['content'])


class RouterAndMemoryTests(unittest.TestCase):
    def test_routes(self):
        cases = {
            'Wie geht es dir?': 'chat', 'Erkläre mir Quantencomputer in zwei Sätzen.': 'chat',
            'Öffne Safari und suche nach den neuesten KI-Entwicklungen.': 'agent',
            'Erstelle eine Excel-Tabelle für meine Unternehmensfinanzen.': 'agent',
            'Analysiere diese PDF und fasse sie zusammen.': 'agent',
            'Atlas, untersuche mein Projekt auf Fehler, behebe sie, teste die Anwendung und erstelle eine neue Version.': 'plan',
            'Aufgabe: räume meinen Schreibtisch auf': 'plan',
            'Nein, ich meinte den Termin am Dienstag.': 'agent',
            'Was siehst du auf meinem Bildschirm?': 'agent',
        }
        for text, expected in cases.items():
            with self.subTest(text=text):
                self.assertEqual(llm.route(text), expected)

    def test_lexical_fallback_and_summary_cache(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        import sqlite3
        import contextlib

        @contextlib.contextmanager
        def connect():
            db = sqlite3.connect(Path(tmp.name) / 'm.db')
            try:
                with db:
                    yield db
            finally:
                db.close()
        index = MemoryIndex(connect)
        memories = [f'Eintrag {i} Garten' for i in range(15)] + ['Fährt einen Tesla Model 3']
        chosen, method = index.relevant('Welches Auto fahre ich, Tesla?', memories, limit=3)
        self.assertEqual(method, 'lexikalisch')
        self.assertIn('Fährt einen Tesla Model 3', chosen)
        calls = []
        first = index.summary([{'role': 'user', 'content': 'Hallo'}], lambda text: calls.append(text) or 'Kurz.')
        second = index.summary([{'role': 'user', 'content': 'Hallo'}], lambda text: calls.append(text) or 'Anders.')
        self.assertEqual((first, second, len(calls)), ('Kurz.', 'Kurz.', 1))

    def test_language_detection(self):
        self.assertEqual(llm.language_of('What is the weather like in London today?'), 'en')
        self.assertEqual(llm.language_of('Wie wird das Wetter heute in Berlin?'), 'de')
        self.assertEqual(llm.language_of('Öffne bitte das Meeting-Dokument'), 'de')
        self.assertEqual(llm.language_of('Ok'), 'de')

    def test_cloud_models_are_rejected(self):
        for name in ('gpt-oss:120b-cloud', 'qwen3-coder:480b-cloud', 'http://evil', ''):
            self.assertFalse(llm.is_local_model(name))
        self.assertTrue(llm.is_local_model('qwen3:8b'))


if __name__ == '__main__':
    unittest.main()
