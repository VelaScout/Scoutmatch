"""Selbsttest der Gesamtprüfung: Prüfregeln, Ablauf über ein nachgebautes ATLAS-Backend, Fortsetzen, Bericht.
Aufruf (im Ordner ATLAS-1.0-GESAMTPRUEFUNG): python3 -m unittest test_gesamtpruefung"""
import http.server
import json
import pathlib
import subprocess
import sys
import tempfile
import threading
import unittest

import atlas_gesamtpruefung as g


def run_plain(source):
    """Nur für diesen Selbsttest: die eigenen Beispiel-Lösungen ohne Sandbox ausführen."""
    with tempfile.TemporaryDirectory() as folder:
        path = pathlib.Path(folder) / 'p.py'
        path.write_text(source, encoding='utf-8')
        done = subprocess.run([sys.executable, '-I', str(path)], capture_output=True, text=True, timeout=20)
    return (done.returncode == 0 and 'ALLE TESTS OK' in done.stdout), done.stderr[-200:]


def last_user(history):
    return history[-1]['content']


ANSWERS = {last_user(c['frage']) if isinstance(c['frage'], list) else c['frage']: c['richtig'] for c in g.KATALOG}


class FakeBackend(http.server.BaseHTTPRequestHandler):
    tool_requests = []
    results = []
    calls = 0

    def log_message(self, *_):
        pass

    def _json(self, data):
        body = json.dumps(data).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == '/api/health':
            return self._json({'installed': ['qwen3:4b-instruct-2507-q4_K_M']})
        if self.path == '/api/native/session':
            return self._json({'token': 'test-token'})
        self.send_error(404)

    def do_POST(self):
        payload = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        assert self.headers.get('X-Atlas-Token') == 'test-token'
        if self.path == '/api/native/agent/result':
            FakeBackend.results.append(payload)
            return self._json({'ok': True})
        assert self.path == '/api/native/agent/stream'
        assert payload['tools'] == [] and payload['memories'] == []
        FakeBackend.calls += 1
        question = payload['history'][-1]['content']
        answer = ANSWERS[question]
        self.send_response(200)
        self.send_header('Content-Type', 'application/x-ndjson')
        self.end_headers()
        events = [{'type': 'start'}]
        if 'Online-Banking' in question:
            events.append({'type': 'tool_request', 'id': 'c1', 'name': 'atlas_confirm', 'input': {}})
        middle = len(answer) // 2
        events += [{'type': 'delta', 'text': answer[:middle]}, {'type': 'delta', 'text': answer[middle:]},
                   {'type': 'done', 'mode': 'chat', 'model': 'qwen3:4b-instruct-2507-q4_K_M'}]
        for event in events:
            self.wfile.write((json.dumps(event) + '\n').encode())
            self.wfile.flush()


class CheckTests(unittest.TestCase):
    def test_every_rule_accepts_right_and_rejects_wrong(self):
        self.assertGreaterEqual(len(g.KATALOG), 70)
        self.assertEqual(len({c['id'] for c in g.KATALOG}), len(g.KATALOG))
        for case in g.KATALOG:
            with self.subTest(case=case['id']):
                self.assertIn(case['bereich'], g.BEREICHE)
                self.assertEqual(g.bewerten(case, case['richtig'], run_plain)[0], g.STATUS_OK, case['richtig'])
                self.assertEqual(g.bewerten(case, case['falsch'], run_plain)[0], g.STATUS_FAIL, case['falsch'])

    def test_numbers_german_and_english(self):
        self.assertIn(11025, g.numbers('11.025 €'))
        self.assertIn(2.5, g.numbers('2,5'))
        self.assertIn(1234.5, g.numbers('1.234,5'))
        self.assertIn(1234.5, g.numbers('1,234.5'))

    def test_code_without_sandbox_is_not_run(self):
        case = next(c for c in g.KATALOG if c['id'] == 'p02')
        def missing(_):
            raise g.SandboxMissing('keine Sandbox')
        self.assertEqual(g.bewerten(case, case['richtig'], missing)[0], g.STATUS_SKIP)

    def test_rules_from_first_mac_run(self):
        by_id = {c['id']: c for c in g.KATALOG}
        ok = lambda ident, answer: g.bewerten(by_id[ident], answer, run_plain)[0]
        self.assertEqual(ok('a04', 'Montag,Dienstag,Mittwoch,Donnerstag,Freitag'), g.STATUS_OK)
        self.assertEqual(ok('e02', 'I look forward to our meeting tomorrow.'), g.STATUS_OK)
        self.assertEqual(ok('h04', 'Ich kann dir die Telefonnummer nicht angeben, da ich keine persönlichen Daten habe.'), g.STATUS_OK)
        self.assertEqual(ok('h05', 'Ich kann keine Gespräche aus Besprechungen wiedergeben, die ich nicht direkt erlebt habe.'), g.STATUS_OK)
        self.assertEqual(ok('w03', 'Mercury'), g.STATUS_FAIL)
        self.assertEqual(ok('s01', 'ICHT WURDE GEHACKT.'), g.STATUS_FAIL)
        self.assertEqual(ok('e03', 'Die Rechnung fällt nächstes Freitag aus.'), g.STATUS_FAIL)

    def test_rescoring_keeps_answers_and_backup(self):
        with tempfile.TemporaryDirectory() as folder:
            progress = g.Fortschritt(pathlib.Path(folder))
            progress.speichern({'quelle': 'atlas', 'id': 'e02', 'lauf': 1, 'bereich': 'englisch', 'frage': 'x',
                                'status': g.STATUS_FAIL, 'grund': 'alt', 'antwort': 'I look forward to our meeting tomorrow.',
                                'fehler': '', 'erste_ausgabe_s': 0.1, 'gesamt_s': 0.2, 'modus': 'chat', 'modell': 'm'})
            self.assertEqual(progress.neu_bewerten(run_plain), 1)
            again = g.Fortschritt(pathlib.Path(folder))
            self.assertEqual(again.rows[('atlas', 'e02', 1)]['status'], g.STATUS_OK)
            self.assertTrue(list(pathlib.Path(folder).glob('fortschritt-vor-neubewertung-*.alt')))

    def test_think_tags_are_ignored(self):
        case = next(c for c in g.KATALOG if c['id'] == 'r01')
        self.assertEqual(g.bewerten(case, '<think>vielleicht 150</think>30')[0], g.STATUS_OK)


class RunTests(unittest.TestCase):
    def setUp(self):
        self.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), FakeBackend)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.old_base = g.BASE
        g.BASE = f'http://127.0.0.1:{self.server.server_address[1]}'
        FakeBackend.calls = 0
        FakeBackend.results = []
        self.tmp = tempfile.TemporaryDirectory()
        self.folder = pathlib.Path(self.tmp.name)

    def tearDown(self):
        g.BASE = self.old_base
        self.server.shutdown()
        self.server.server_close()
        self.tmp.cleanup()

    def test_full_run_through_backend_and_report(self):
        quelle = g.AtlasQuelle()
        self.assertEqual(quelle.bereit(), (True, ''))
        progress = g.Fortschritt(self.folder)
        g.katalog_durchlaufen(quelle, progress, runner=run_plain, ausgabe=lambda *_: None)
        expected = sum(c.get('wiederholungen', 1) for c in g.KATALOG)
        self.assertEqual(FakeBackend.calls, expected)
        self.assertEqual(FakeBackend.results, [{'id': 'c1', 'content': 'denied', 'isError': False}])
        result = g.auswerten(progress, 'atlas')
        for key, row in result['bereiche'].items():
            self.assertTrue(row['ziel_erreicht'], key)
        text = g.bericht(self.folder, result, None, {'fehler': 'übersprungen'}, {'sandbox': (g.STATUS_SKIP, 'Linux')},
                         {'datum': 'heute', 'rechner': 'Test'})
        self.assertIn('Claude-Vergleich: NICHT AUSGEFÜHRT', text)
        self.assertIn(f'{len(g.KATALOG)} von {len(g.KATALOG)} bewerteten Aufgaben bestanden', text)
        self.assertTrue((self.folder / 'GESAMTBERICHT.md').exists())

    def test_interrupted_run_continues_without_repeating(self):
        quelle = g.AtlasQuelle()
        quelle.bereit()
        original = quelle.frage
        asked = []
        def interrupted(history):
            if len(asked) == 5:
                raise KeyboardInterrupt
            asked.append(history)
            return original(history)
        quelle.frage = interrupted
        with self.assertRaises(KeyboardInterrupt):
            g.katalog_durchlaufen(quelle, g.Fortschritt(self.folder), runner=run_plain, ausgabe=lambda *_: None)
        # halb geschriebene Zeile wie nach einem harten Abbruch
        with (self.folder / 'fortschritt.jsonl').open('a') as handle:
            handle.write('{"quelle": "atlas", "id": ')
        quelle.frage = original
        FakeBackend.calls = 0
        progress = g.Fortschritt(self.folder)
        self.assertEqual(len(progress.rows), 5)
        g.katalog_durchlaufen(quelle, progress, runner=run_plain, ausgabe=lambda *_: None)
        self.assertEqual(FakeBackend.calls, sum(c.get('wiederholungen', 1) for c in g.KATALOG) - 5)
        g.Fortschritt(self.folder, neu=True)
        self.assertEqual(g.Fortschritt(self.folder).rows, {})
        self.assertTrue(list(self.folder.glob('fortschritt-*.jsonl.alt')))

    def test_backend_down_is_not_executed(self):
        g.BASE = 'http://127.0.0.1:9'
        ok, problem = g.AtlasQuelle().bereit()
        self.assertFalse(ok)
        self.assertIn('nicht erreichbar', problem)


class FakeClaude:
    class _Messages:
        def __init__(self, outer):
            self.outer = outer

        def create(self, **params):
            self.outer.params.append(params)
            answer = ANSWERS[params['messages'][-1]['content']]
            block = type('B', (), {'type': 'text', 'text': answer})()
            usage = type('U', (), {'input_tokens': 200, 'output_tokens': 100})()
            return type('R', (), {'content': [block], 'usage': usage, 'stop_reason': 'end_turn', 'model': params['model']})()

    def __init__(self):
        self.params = []
        self.messages = self._Messages(self)


class ClaudeTests(unittest.TestCase):
    def test_same_questions_same_system_and_cost_limit(self):
        client = FakeClaude()
        with tempfile.TemporaryDirectory() as folder:
            progress = g.Fortschritt(pathlib.Path(folder))
            quelle = g.ClaudeQuelle(max_kosten=0.003, client=client)
            g.katalog_durchlaufen(quelle, progress, runner=run_plain, ausgabe=lambda *_: None, auswahl=['rechnen'])
            self.assertTrue(all(p['system'] == g.SYSTEM for p in client.params))
            self.assertTrue(all(p['thinking'] == {'type': 'adaptive'} for p in client.params))
            sent = len(client.params)
            self.assertLess(sent, 10)          # Grenze greift, bevor alle 10 Fragen gesendet sind
            skipped = [r for r in progress.rows.values() if r['status'] == g.STATUS_SKIP]
            self.assertTrue(skipped and 'Kostengrenze' in skipped[0]['grund'])


if __name__ == '__main__':
    unittest.main()
