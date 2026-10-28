"""Regression checks for source provenance and topic cleanup."""
import contextlib
import sqlite3
import tempfile
import unittest
from pathlib import Path
from atlas.knowledge import Knowledge

class KnowledgeSafetyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / 'atlas.sqlite'

    @contextlib.contextmanager
    def connect(self):
        db = sqlite3.connect(self.path)
        try:
            with db:
                yield db
        finally:
            db.close()

    def test_independent_source_not_double_counted(self):
        k = Knowledge(self.connect)
        with self.connect() as db:
            db.execute("INSERT INTO knowledge_topics(topic,status,created_at,updated_at) VALUES ('Physik','gelernt','2026-01-01','2026-01-01')")
        statement = 'Gravitation beschreibt eine Wechselwirkung zwischen Massen.'
        k._store(1, statement, 'fakt', 'https://example.org/a', 'A')
        k._store(1, statement, 'fakt', 'https://example.org/b', 'B')
        k._store(1, statement, 'fakt', 'https://example.org/b', 'B')
        with self.connect() as db:
            support = db.execute('SELECT support FROM knowledge_facts').fetchone()[0]
        self.assertEqual(support, 2)

    def test_topic_delete_cleans_search_index(self):
        k = Knowledge(self.connect)
        with self.connect() as db:
            db.execute("INSERT INTO knowledge_topics(topic,status,created_at,updated_at) VALUES ('Physik','gelernt','2026-01-01','2026-01-01')")
        k._store(1, 'Gravitation beschreibt die Anziehung zwischen Massen.', 'fakt', 'https://example.org/a', 'A')
        self.assertTrue(k.delete('topic', 1))
        self.assertEqual(k.audit()['facts'], 0)
        self.assertEqual(k.context_for('Gravitation'), '')
