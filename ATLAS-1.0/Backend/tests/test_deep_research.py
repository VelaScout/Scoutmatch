import unittest
from unittest.mock import patch
from atlas.research import deep_research, research_plan
from atlas.tools import Result

class DeepResearchTests(unittest.TestCase):
    def test_plan_bounded(self):
        self.assertEqual(len(research_plan('Physik', 100)), 5)
        self.assertEqual(research_plan(''), [])
    def test_dedup_and_failures(self):
        def fake(env, question, max_sources=4):
            if 'Risiken' in question:
                return Result(False, 'offline', data={'sources': []})
            return Result(True, 'ok', data={'sources': [{'url':'https://example.org/a','title':'A','n':1}]})
        with patch('atlas.research.research', side_effect=fake):
            result = deep_research(None, 'Physik')
        self.assertTrue(result.ok)
        self.assertEqual(len(result.data['sources']), 1)
        self.assertEqual(len(result.data['failed_queries']), 1)
    def test_rejects_empty(self):
        with self.assertRaises(Exception):
            deep_research(None, '')
