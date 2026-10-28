import unittest
from atlas.benchmark_summary import summarize

class SummaryTests(unittest.TestCase):
    def test_blocked_not_success(self):
        x = summarize([{'status':'PASS','seconds':2}, {'status':'BLOCKED','seconds':0}])
        self.assertEqual(x['pass_rate_percent'],100)
        self.assertEqual(x['coverage_percent'],50)
        self.assertFalse(x['ready_for_comparison'])
    def test_only_blocked(self):
        x = summarize([{'status':'BLOCKED'}])
        self.assertIsNone(x['pass_rate_percent'])
        self.assertIsNone(x['median_seconds'])
    def test_fail_rate(self):
        x = summarize([{'status':'FAIL','seconds':4},{'status':'PASS','seconds':2}])
        self.assertEqual(x['pass_rate_percent'],50)
        self.assertEqual(x['median_seconds'],3)
    def test_empty(self):
        self.assertEqual(summarize([])['coverage_percent'],None)
    def test_ready_requires_ten(self):
        self.assertFalse(summarize([{'status':'PASS'}]*9)['ready_for_comparison'])
        self.assertTrue(summarize([{'status':'PASS'}]*10)['ready_for_comparison'])
    def test_missing_timing(self):
        self.assertIsNone(summarize([{'status':'PASS'}])['median_first_token_seconds'])
    def test_invalid_negative_timing(self):
        self.assertIsNone(summarize([{'status':'FAIL','seconds':-3}])['median_seconds'])

if __name__ == '__main__': unittest.main()
