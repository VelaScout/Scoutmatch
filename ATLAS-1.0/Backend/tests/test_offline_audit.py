import unittest
from pathlib import Path
from atlas.offline_audit import audit
from atlas.intelligence_benchmark import safe_local_url

class OfflineAuditTests(unittest.TestCase):
    def test_project_structure(self):
        root = Path(__file__).resolve().parents[2]
        result = audit(root)
        self.assertEqual(result['passed'], result['total'], result)
    def test_local_only_benchmark(self):
        self.assertEqual(safe_local_url('http://127.0.0.1:11434'), 'http://127.0.0.1:11434')
        for url in ['https://127.0.0.1:11434','http://example.com','http://127.0.0.1@evil.test','http://127.0.0.1:11434/api','file:///etc/passwd']:
            with self.subTest(url=url), self.assertRaises(ValueError): safe_local_url(url)

if __name__ == '__main__': unittest.main()
