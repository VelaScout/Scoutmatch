import unittest
from atlas.reasoning_engine import solve

class FakeLLM:
    def __init__(self, responses):
        self.responses = iter(responses)
        self.calls = []
    def chat(self, model, messages, **kwargs):
        self.calls.append((model, messages, kwargs))
        return type('Reply', (), {'content': next(self.responses)})()

class Tests(unittest.TestCase):
    def test_three_calls_and_independence(self):
        llm = FakeLLM(['Erster Ansatz', 'Zweiter Ansatz', 'Endantwort'])
        result = solve(llm, 'local', [{'role': 'user', 'content': 'Frage'}])
        self.assertEqual(result.answer, 'Endantwort')
        self.assertEqual(result.calls, 3)
        self.assertNotIn('Erster Ansatz', str(llm.calls[1][1]))
        self.assertIn('Erster Ansatz', str(llm.calls[2][1]))
        self.assertIn('Zweiter Ansatz', str(llm.calls[2][1]))
    def test_empty_draft_fails(self):
        with self.assertRaises(ValueError):
            solve(FakeLLM(['']), 'local', [])
    def test_empty_review_fails(self):
        with self.assertRaises(ValueError):
            solve(FakeLLM(['a', 'b', '']), 'local', [])
    def test_cancel_before_start(self):
        class Stop:
            def is_set(self): return True
        llm = FakeLLM([])
        result = solve(llm, 'local', [], stop=Stop())
        self.assertEqual(result.calls, 0)
        self.assertEqual(llm.calls, [])
    def test_disagreement_flag(self):
        result = solve(FakeLLM(['a', 'b', 'c']), 'local', [])
        self.assertTrue(result.disagreement)
