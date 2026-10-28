"""Fehlerfälle, Migration und Leistung des Backends.

Simuliert: Sprachmodell (FakeOllama), Internet (Fehler beim Abruf). Echt: Server, Datenbank,
Zeitmessung und Speichermessung – aber in der Linux-Entwicklungsumgebung, NICHT auf dem Mac
und OHNE echtes Modell. Die Zahlen zeigen nur den Eigenaufwand von ATLAS, nicht die Modellzeit.
"""
import json
import sqlite3
import statistics
import tempfile
import threading
import time
import tracemalloc
import unittest
import urllib.error
from pathlib import Path

from atlas import agent as a
from atlas import llm
from atlas import server as s
from atlas import tools as t
from atlas.memory import MemoryIndex
from fake_ollama import FakeOllama, answer, tool_call
import test_agent
from test_tools import FakeRunner


class FailureTests(test_agent.AgentServerTests):
    """Nutzt Server und Testclient aus test_agent, ersetzt aber die Testfälle."""

    def test_ollama_unreachable_gives_clear_message(self):
        dead = llm.Ollama(base='http://127.0.0.1:9')   # Port ohne Dienst
        self.agent.llm = dead
        for question in ('Wie geht es dir?', 'Erstelle einen Ordner Test in Dokumente'):
            with self.subTest(question=question):
                _, events = self.run_agent(self.body(question))
                self.assertEqual(events[-1]['type'], 'error')
                self.assertIn('Ollama ist nicht erreichbar', events[-1]['error'])
        # Direkte Rechnungen funktionieren trotzdem.
        _, events = self.run_agent(self.body('Was ist 12 mal 12?'))
        self.assertEqual(self.text(events), '144.')

    def test_broken_model_output_is_reported_not_crashing(self):
        self.ollama.broken = True
        _, events = self.run_agent(self.body('Erstelle einen Ordner Test in Dokumente'))
        self.assertEqual(events[-1]['type'], 'error')
        self.assertIn('unverständliche Antwort', events[-1]['error'])
        # Der Server bleibt nutzbar.
        self.ollama.broken = False
        self.ollama.stream_text = ['Wieder da.']
        _, events = self.run_agent(self.body('Wie geht es dir?'))
        self.assertEqual(self.text(events), 'Wieder da.')

    def test_incomplete_stream_is_an_error(self):
        self.ollama.stream_incomplete = True
        _, events = self.run_agent(self.body('Erzähl mir etwas über Berlin.'))
        self.assertEqual(events[-1]['type'], 'error')

    def test_unknown_tool_and_wrong_arguments_are_survived(self):
        self.ollama.script = [tool_call('format_disk', target='/'), tool_call('create_folder', path=12345),
                              tool_call('create_folder'), answer('Das ging leider nicht.')]
        _, events = self.run_agent(self.body('Erstelle einen Ordner in Dokumente'))
        self.assertEqual(events[-1]['type'], 'done')
        messages = [m for m in self.ollama.chat_requests()[-1]['messages'] if m['role'] == 'tool']
        self.assertIn('Unbekanntes Werkzeug', messages[0]['content'])
        self.assertIn('Pfad fehlt', messages[1]['content'])
        self.assertIn('Fehlende Angaben', messages[2]['content'])
        self.assertEqual(list((self.home / 'Documents').iterdir()), [])

    def test_offline_internet(self):
        def offline(url, timeout):
            raise urllib.error.URLError('Keine Verbindung')
        env = t.Environment(home=self.home, roots=[self.home], runner=FakeRunner(), fetch=offline, is_mac=False)
        self.agent.base_tools = t.build_tools(env)
        self.ollama.script = [tool_call('search_web', query='Wetter Berlin'), answer('Ich bin gerade offline.')]
        _, events = self.run_agent(self.body('Suche im Internet nach dem Wetter in Berlin'))
        tool_message = [m for m in self.ollama.chat_requests()[1]['messages'] if m['role'] == 'tool'][0]
        self.assertFalse(json.loads(tool_message['content'])['ok'])
        self.assertIn('offline', self.text(events))
        self.assertEqual(events[-1]['type'], 'done')

    def test_model_timeout_is_clear(self):
        self.ollama.delay = 3
        self.agent.llm = llm.Ollama(base=self.ollama.url)
        original = self.agent.llm.chat
        self.agent.llm.chat = lambda *args, **kwargs: original(*args, **{**kwargs, 'timeout': 0.5})
        self.ollama.script = [answer('zu spät')]
        _, events = self.run_agent(self.body('Erstelle einen Ordner in Dokumente'))
        self.assertEqual(events[-1]['type'], 'error')
        self.assertIn('nicht rechtzeitig', events[-1]['error'])


class MigrationTests(unittest.TestCase):
    def test_old_database_keeps_all_rows(self):
        with tempfile.TemporaryDirectory() as folder:
            db_path = Path(folder) / 'atlas.db'
            old = sqlite3.connect(db_path)
            old.execute('CREATE TABLE messages (id INTEGER PRIMARY KEY, role TEXT NOT NULL, content TEXT NOT NULL, created_at TEXT NOT NULL)')
            old.execute('CREATE TABLE memories (id INTEGER PRIMARY KEY, content TEXT NOT NULL, created_at TEXT NOT NULL)')
            old.executemany('INSERT INTO messages(role,content,created_at) VALUES (?,?,?)',
                            [('user', f'Frage {i}', '2026-01-01T00:00:00+00:00') for i in range(50)])
            old.execute("INSERT INTO memories(content,created_at) VALUES ('Mag Tee','2026-01-01T00:00:00+00:00')")
            old.commit()
            old.close()
            previous = (s.DATA, s.DB)
            s.DATA, s.DB = Path(folder), db_path
            try:
                MemoryIndex(s.database)                       # legt neue Tabellen an
                with s.database() as db:
                    self.assertEqual(db.execute('SELECT count(*) FROM messages').fetchone()[0], 50)
                    self.assertEqual(db.execute('SELECT content FROM memories').fetchone()[0], 'Mag Tee')
                    tables = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
                self.assertTrue({'messages', 'memories', 'embeddings', 'summaries'} <= tables)
                MemoryIndex(s.database)                       # zweiter Start: nichts kaputt
            finally:
                s.DATA, s.DB = previous


class PerformanceTests(unittest.TestCase):
    """Eigenaufwand von ATLAS (ohne Modellzeit), gemessen in der Entwicklungsumgebung."""

    @classmethod
    def setUpClass(cls):
        cls.results = {}

    def test_overhead_until_first_word(self):
        ollama = FakeOllama()
        self.addCleanup(ollama.close)
        ollama.stream_text = ['Hallo.']
        agent = a.Agent(llm.Ollama(base=ollama.url), {}, a.Bridge())
        request = a.Request(system='Test', history=[{'role': 'user', 'content': 'Wie geht es dir?'}])
        timings = []
        for _ in range(20):
            started = time.perf_counter()
            for event in agent.run(request, threading.Event()):
                if event['type'] == 'delta':
                    timings.append((time.perf_counter() - started) * 1000)
                    break
        median = statistics.median(timings)
        print(f'\n[Messung Linux, Modell simuliert] Eigenaufwand bis zum ersten Wort: Median {median:.1f} ms')
        self.assertLess(median, 150)

    def test_memory_selection_is_fast_and_small(self):
        index = MemoryIndex(lambda: _memory_db())
        memories = [f'[Notiz] Eintrag Nummer {i} über Thema {i % 37} und Projekt {i % 11}' for i in range(500)]
        tracemalloc.start()
        started = time.perf_counter()
        for _ in range(20):
            index.relevant('Was weiß ich über Projekt 7?', memories, limit=8)
        elapsed = (time.perf_counter() - started) / 20 * 1000
        peak = tracemalloc.get_traced_memory()[1] / 1e6
        tracemalloc.stop()
        print(f'\n[Messung Linux] Erinnerungsauswahl aus 500 Einträgen: {elapsed:.1f} ms, Speicherspitze {peak:.1f} MB')
        self.assertLess(elapsed, 100)
        self.assertLess(peak, 20)


_db_path = Path(tempfile.mkdtemp()) / 'perf.db'


def _memory_db():
    import contextlib

    @contextlib.contextmanager
    def connect():
        db = sqlite3.connect(_db_path)
        try:
            with db:
                yield db
        finally:
            db.close()
    return connect()


# Die Testfälle der Basisklasse nicht doppelt ausführen.
for _name in [n for n in vars(test_agent.AgentServerTests) if n.startswith('test_')]:
    if _name not in vars(FailureTests):
        setattr(FailureTests, _name, None)

if __name__ == '__main__':
    unittest.main()
