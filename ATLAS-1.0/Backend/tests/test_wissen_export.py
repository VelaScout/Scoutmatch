import importlib.util
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'tools' / 'wissen_export.py'
spec=importlib.util.spec_from_file_location('wissen_export', SCRIPT)
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class ExportTests(unittest.TestCase):
    def test_roundtrip_provenance_and_read_only(self):
        with tempfile.TemporaryDirectory() as d:
            db=Path(d)/'atlas.db'; out=Path(d)/'wissen.json'
            with sqlite3.connect(db) as con:
                con.execute('CREATE TABLE knowledge_topics(id INTEGER, topic TEXT)')
                con.execute('CREATE TABLE knowledge_facts(id INTEGER, topic_id INTEGER, statement TEXT, source_url TEXT)')
                con.execute('INSERT INTO knowledge_topics VALUES(1, ?)', ('Quantenphysik',))
                con.execute('INSERT INTO knowledge_facts VALUES(1,1,?,?)', ('Elektronen haben Spin', 'https://example.org'))
            self.assertEqual(mod.export(db,out),(1,1))
            data=json.loads(out.read_text())
            self.assertEqual(data['facts'][0]['source_url'],'https://example.org')
            self.assertEqual(data['topics'][0]['topic'],'Quantenphysik')
    def test_missing_database_does_not_create_it(self):
        with tempfile.TemporaryDirectory() as d:
            db=Path(d)/'missing.db'
            with self.assertRaises(FileNotFoundError): mod.export(db,Path(d)/'x.json')
            self.assertFalse(db.exists())

if __name__=='__main__': unittest.main()
