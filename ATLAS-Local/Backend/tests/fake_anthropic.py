"""Nachgebaute Anthropic-API für Tests: echter HTTP-Server, das offizielle SDK spricht wirklich mit ihm.
Antworten werden pro Test vorgegeben; alle Anfragen (Kopfzeilen und Inhalt) werden mitgeschnitten."""
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def message(content, stop='end_turn', input_tokens=1000, output_tokens=200, model='claude-opus-5-5', iterations=None):
    usage = {'input_tokens': input_tokens, 'output_tokens': output_tokens}
    if iterations:
        usage['iterations'] = iterations
    return {'id': 'msg_test', 'type': 'message', 'role': 'assistant', 'model': model, 'content': content,
            'stop_reason': stop, 'stop_sequence': None, 'usage': usage}


class FakeAnthropic:
    def __init__(self):
        self.script, self.requests = [], []
        fake = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
                fake.requests.append({'path': self.path, 'headers': dict(self.headers), 'body': body})
                reply = fake.script.pop(0) if fake.script else message([{'type': 'text', 'text': 'Leer'}])
                data = json.dumps(reply).encode()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                self.wfile.write(data)

        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.url = f'http://127.0.0.1:{self.server.server_port}'
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def close(self):
        self.server.shutdown()
        self.server.server_close()
