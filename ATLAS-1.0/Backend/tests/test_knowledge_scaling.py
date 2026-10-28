"""Offline integration tests for persistent knowledge search and audit."""
import contextlib
import sqlite3
import tempfile
import unittest
from pathlib import Path
from atlas.knowledge import Knowledge


class KnowledgeScalingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.dbpath = Path(self.temp.name)/'memory.db'

    @contextlib.contextmanager
    def connect(self):
        db = sqlite3.connect(self.dbpath)
        try:
            with db:
                yield db
        finally:
            db.close()

    def test_index_rebuild_on_restart_and_retrieval(self):
        memory = Knowledge(self.connect)
        with self.connect() as db:
            db.execute("INSERT INTO knowledge_topics(topic,status,created_at,updated_at) VALUES ('Physik','gelernt','2026-01-01','2026-01-01')")
        memory._store(1, 'Die Gravitation ist eine grundlegende Wechselwirkung zwischen Massen.', 'fakt', 'https://example.org/physics', 'Physikquelle')
        self.assertIn('Gravitation', memory.context_for('Was ist Gravitation?'))
        self.assertEqual(Knowledge(self.connect).audit()['facts'], 1)
        with self.connect() as db:
            db.execute('DROP TRIGGER knowledge_facts_ai')
            db.execute("INSERT INTO knowledge_facts(topic_id,statement,kind,status,source_url,source_title,retrieved_at) VALUES (1,'Die Magnetisierung hängt vom Material ab.','fakt','belegt','https://example.org/magnet','Magnet','2026-01-01')")
        rebuilt = Knowledge(self.connect)
        self.assertIn('Magnetisierung', rebuilt.context_for('Was bedeutet Magnetisierung?'))

    def test_fallback_does_not_scan_every_fact(self):
        k = Knowledge(self.connect)
        with self.connect() as db:
            db.execute("INSERT INTO knowledge_topics(topic,status,created_at,updated_at) VALUES ('Astronomie','gelernt','2026-01-01','2026-01-01')")
        k._store(1, 'Planetenbahnen werden durch Gravitation beeinflusst.', 'fakt', 'https://example.org', 'Quelle')
        # An unrelated question must not pull all records into the fallback.
        self.assertEqual(k.context_for('Wie funktioniert Photosynthese?'), '')
        self.assertIn('Planetenbahnen', k.context_for('Planetenbahnen Gravitation'))

    def test_edit_delete_and_audit(self):
        k = Knowledge(self.connect)
        with self.connect() as db:
            db.execute("INSERT INTO knowledge_topics(topic,status,created_at,updated_at) VALUES ('Sport','gelernt','2026-01-01','2026-01-01')")
        k._store(1, 'Ausdauertraining kann die aerobe Leistungsfähigkeit erhöhen.', 'fakt', 'https://example.org/sport', 'Sportquelle')
        with self.connect() as db:
            fid = db.execute('SELECT id FROM knowledge_facts').fetchone()[0]
        self.assertTrue(k.edit_fact(fid, statement='Das Laufen erfordert eine koordinierte Muskelarbeit.'))
        self.assertIn('Laufen', k.context_for('Laufen koordinierte Muskelarbeit'))
        self.assertTrue(k.delete('fact', fid))
        self.assertEqual(k.audit()['facts'], 0)
        self.assertEqual(k.audit()['thin_topics'], 1)

if __name__ == '__main__':
    unittest.main()
