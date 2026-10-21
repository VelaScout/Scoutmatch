"""Simuliertes Ollama für Tests: echter HTTP-Server mit vorgegebenen Antworten.

Kein echtes Sprachmodell – die Antworten werden pro Test vorgegeben. So lässt sich prüfen,
was der Agent mit Werkzeugaufrufen tatsächlich macht (Dateien, Bestätigungen, Fehler …).
"""
import json
import re
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def tool_call(name, **arguments):
    return {'message': {'role': 'assistant', 'content': '', 'tool_calls': [
        {'function': {'name': name, 'arguments': arguments}}]}, 'done': True, 'eval_count': 10, 'eval_duration': 10**8}


def answer(text):
    return {'message': {'role': 'assistant', 'content': text}, 'done': True, 'eval_count': 5, 'eval_duration': 10**8}


class FakeOllama:
    def __init__(self, models=('qwen3:4b', 'qwen3:8b')):
        self.models = list(models)
        self.script = []          # Antworten für nicht-streamende /api/chat-Aufrufe
        self.stream_text = ['Hallo ', 'Sir.']
        self.requests = []
        self.embed_calls = 0
        self.delay = 0.0
        fake = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                if self.path == '/api/tags':
                    self.reply({'models': [{'name': n} for n in fake.models]})
                else:
                    self.reply({'error': 'not found'}, 404)

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
                fake.requests.append((self.path, body))
                if self.path == '/api/embed':
                    fake.embed_calls += 1
                    self.reply({'embeddings': [fake.vector(t) for t in body['input']]})
                    return
                if body.get('stream'):
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/x-ndjson')
                    self.end_headers()
                    for piece in fake.stream_text:
                        self.wfile.write((json.dumps({'message': {'content': piece}, 'done': False}) + '\n').encode())
                    self.wfile.write((json.dumps({'done': True, 'done_reason': 'stop'}) + '\n').encode())
                    return
                if fake.delay:
                    threading.Event().wait(fake.delay)
                item = fake.script.pop(0) if fake.script else answer('Fertig.')
                if callable(item):
                    item = item(body)
                self.reply(item)

            def reply(self, obj, status=200):
                data = json.dumps(obj).encode()
                self.send_response(status)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                self.wfile.write(data)

        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = f'http://127.0.0.1:{self.server.server_port}'

    @staticmethod
    def vector(text):
        """Deterministischer Themen-Vektor: ähnliche Wörter → ähnliche Vektoren."""
        topics = [r'kaffee|espresso|cappuccino', r'auto|fahr|tesla', r'sport|lauf|fitness', r'arbeit|projekt|firma',
                  r'musik|song|spotify', r'essen|vegetar|kochen', r'anrede|herr|sir']
        lowered = text.lower()
        return [float(len(re.findall(t, lowered))) + 0.01 for t in topics]

    def chat_requests(self):
        return [body for path, body in self.requests if path == '/api/chat']

    def close(self):
        self.server.shutdown()
        self.server.server_close()
