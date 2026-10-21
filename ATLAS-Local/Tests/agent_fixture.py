"""Testumgebung für die Swift-Vertragstests auf dem Mac: ECHTES Atlas-Backend + simuliertes Ollama.

Die Swift-App spricht mit dem echten Server-Code (Protokoll, Werkzeuge, Bestätigungen,
Dateien in einem temporären Home-Ordner). Nur das Sprachmodell ist vorgegeben – so ist das
Ergebnis reproduzierbar. Echte Nutzerdaten werden nie berührt.

Aufruf: python3 Tests/agent_fixture.py <port-datei> <home-datei>
"""
import json
import sys
import tempfile
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(ROOT / 'Backend'), str(ROOT / 'Backend' / 'tests')]

from atlas import agent as a, llm, server as s, tools as t  # noqa: E402
from atlas.memory import MemoryIndex  # noqa: E402
from fake_ollama import FakeOllama, answer, tool_call  # noqa: E402

work = Path(tempfile.mkdtemp(prefix='atlas-fixture-'))
home = work / 'home'
for name in ('Desktop', 'Documents', 'Downloads'):
    (home / name).mkdir(parents=True)
(home / 'Documents' / 'alt.txt').write_text('bleibt')
s.DATA = work / 'data'
s.DB = s.DATA / 'atlas.db'

ollama = FakeOllama()
ollama.stream_text = ['Hallo ', 'Robin']


def last_user(body):
    users = [m['content'] for m in body['messages'] if m['role'] == 'user']
    return users[-1] if users else ''


def responder(body):
    messages = body['messages']
    if messages[-1]['role'] == 'tool':
        content = messages[-1]['content']
        try:
            content = json.loads(content).get('output', content)
        except ValueError:
            pass
        return answer('Ergebnis: ' + str(content)[:200])
    text = last_user(body)
    if 'Testordner' in text:
        return tool_call('create_folder', path='~/Desktop/Testordner')
    if 'Kalender' in text:
        return tool_call('get_calendar_events', days=1)
    if 'alt.txt' in text:
        return tool_call('delete_path', path='~/Documents/alt.txt')
    if 'Fehler-Test' in text:
        return {'error': 'Testfehler'}
    return answer('Fertig.')


ollama.responder = responder
client = llm.Ollama(base=ollama.url)
s.OLLAMA_CLIENT = client
env = t.Environment(home=home, roots=[home], is_mac=False)
s._AGENT = a.Agent(client, t.build_tools(env), s.BRIDGE, MemoryIndex(s.database, client.embed),
                   limits=a.Limits(max_rounds=4, seconds=30, native_timeout=20))
s.TOKEN = 'fixture'

server = s.ThreadingHTTPServer(('127.0.0.1', 0), s.Handler)
Path(sys.argv[2]).write_text(str(home))
Path(sys.argv[1]).write_text(str(server.server_port))
server.serve_forever()
