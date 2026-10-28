import unittest
from atlas.oneclick_intelligence import choose_models, report_markdown

class OneClickTests(unittest.TestCase):
    def test_prioritizes_8b(self):
        self.assertEqual(choose_models(['qwen3:4b', 'qwen3:8b'])[0], 'qwen3:8b')
    def test_blocks_cloud(self):
        self.assertEqual(choose_models(['qwen3:8b-cloud', 'qwen3:4b']), ['qwen3:4b'])
    def test_empty(self):
        self.assertEqual(choose_models([]), [])
    def test_report_disclaims_equivalence(self):
        result = {'timestamp': 'now', 'benchmarks': [], 'ab': None}
        self.assertIn('kein ChatGPT-', report_markdown(result))
