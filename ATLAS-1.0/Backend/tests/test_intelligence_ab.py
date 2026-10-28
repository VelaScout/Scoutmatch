import unittest
from atlas.intelligence_ab import paired_trial, summarize

class TestAB(unittest.TestCase):
    def test_improvement(self):
        answers = iter(['wrong', 'wrong', '42'])
        def fake(*args): return next(answers)
        r = paired_trial('fake', 'test', '42', '', 1, fake)
        self.assertFalse(r['direct']['correct'])
        self.assertTrue(r['reviewed']['correct'])
        self.assertTrue(summarize([r])['review_is_better'])
    def test_regression(self):
        answers = iter(['42', '42', 'wrong'])
        r = paired_trial('fake', 'test', '42', '', 1, lambda *args: next(answers))
        self.assertEqual(summarize([r])['regressed'], 1)
        self.assertFalse(summarize([r])['review_is_better'])
    def test_incomplete_not_better(self):
        def fail(*args): raise OSError('offline')
        r = paired_trial('fake', 'test', '42', '', 1, fail)
        self.assertFalse(summarize([r])['complete'])
        self.assertFalse(summarize([r])['review_is_better'])
    def test_equal_not_better(self):
        answers = iter(['42', '42', '42'])
        r = paired_trial('fake', 'test', '42', '', 1, lambda *args: next(answers))
        self.assertFalse(summarize([r])['review_is_better'])
