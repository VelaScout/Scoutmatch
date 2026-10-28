import unittest
from atlas.intelligence_benchmark import summarize_trials

def trial(correct, error=False):
    return {'attempted': 1 if error else 2, 'total': 2, 'passed': sum(correct),
            'results': [{'passed': c} for c in correct]}

class ReliabilityTests(unittest.TestCase):
    def test_empty(self):
        self.assertFalse(summarize_trials([])['eligible'])
    def test_consistent(self):
        r = summarize_trials([trial([True, False]), trial([True, False])])
        self.assertEqual(r['consistency'], .5)
        self.assertEqual(r['accuracy'], .5)
    def test_inconsistent(self):
        r = summarize_trials([trial([True, False]), trial([False, True])])
        self.assertEqual(r['consistency'], 0)
        self.assertEqual(r['accuracy'], .5)
    def test_failed_request_disqualifies(self):
        self.assertFalse(summarize_trials([trial([True, True]), trial([True, False], error=True)])['eligible'])
