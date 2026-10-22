"""Stabilität bei längerer Nutzung: 300 Anfragen hintereinander (Gespräch, Werkzeuge, Fehler, Abbruch).

Echt: Agent, Server-Brücke, Dateien, SQLite-Journal. Simuliert: das Sprachmodell (FakeOllama).
Geprüft: keine wachsenden Threads, offenen Dateien oder wartenden App-Anfragen; Speicher wächst nicht unbegrenzt.
Ob das echte Modell über Stunden stabil läuft, zeigt nur die Nutzung auf dem Mac (NICHT AUSGEFÜHRT hier).
"""
import contextlib
import gc
import os
import sqlite3
import tempfile
import threading
import tracemalloc
import unittest
from pathlib import Path

from atlas import agent as a
from atlas import llm
from atlas.tasks import TaskJournal
from atlas.tools import Environment, build_tools
from fake_ollama import FakeOllama, answer, tool_call


def open_files() -> int:
    path = Path('/proc/self/fd')
    return len(list(path.iterdir())) if path.exists() else 0


class StabilityTests(unittest.TestCase):
    def test_three_hundred_requests_do_not_leak(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve()
            (root / 'Documents').mkdir()

            @contextlib.contextmanager
            def connect():
                db = sqlite3.connect(root / 'atlas.db')
                try:
                    with db:
                        yield db
                finally:
                    db.close()
            ollama = FakeOllama()
            self.addCleanup(ollama.close)
            ollama.stream_text = ['Gern.']
            agent = a.Agent(llm.Ollama(base=ollama.url), build_tools(Environment(home=root, roots=[root], is_mac=False)),
                            a.Bridge(), journal=TaskJournal(connect), limits=a.Limits(max_rounds=4, seconds=20, native_timeout=1))

            def one(i):
                kind = i % 4
                stop = threading.Event()
                if kind == 0:
                    text = f'Wie geht es dir heute, Runde {i}?'
                elif kind == 1:
                    ollama.script = [tool_call('create_folder', path=f'~/Documents/Ordner {i}'), answer('Angelegt.')]
                    text = f'Erstelle in Dokumente einen Ordner Ordner {i}'
                elif kind == 2:
                    ollama.script = [tool_call('read_file', path='~/Documents/fehlt.pdf'), answer('Fehlt.'), answer('Fehlt.')]
                    text = 'Lies Dokumente/fehlt.pdf und fasse sie zusammen'
                else:
                    stop.set()                                   # sofort abgebrochen
                    text = f'Erstelle in Dokumente eine Datei abbruch{i}.txt'
                events = list(agent.run(a.Request(system='ATLAS', history=[{'role': 'user', 'content': text}]), stop))
                ollama.requests.clear()                          # Mitschnitt des Test-Modells nicht mitzählen
                return events

            for i in range(20):                                   # Aufwärmen (Caches, Verbindungen)
                one(i)
            gc.collect()
            threads, files = threading.active_count(), open_files()
            tracemalloc.start()
            before = tracemalloc.take_snapshot()
            for i in range(20, 300):
                events = one(i)
                self.assertIn(events[-1]['type'], ('done', 'cancelled'), events[-1])
            gc.collect()
            after = tracemalloc.take_snapshot()
            tracemalloc.stop()
            growth = sum(s.size_diff for s in after.compare_to(before, 'filename'))
            self.assertLessEqual(threading.active_count(), threads + 2)
            if files:
                self.assertLessEqual(open_files(), files + 5)
            self.assertEqual(agent.bridge.waiting, {})
            self.assertLess(growth, 1024 * 1024, f'Speicher wuchs um {growth} Bytes')
            self.assertEqual(len(list((root / 'Documents').glob('Ordner *'))), 75)
            with connect() as db:
                self.assertGreaterEqual(db.execute('SELECT count(*) FROM tasks').fetchone()[0], 140)


if __name__ == '__main__':
    unittest.main()
