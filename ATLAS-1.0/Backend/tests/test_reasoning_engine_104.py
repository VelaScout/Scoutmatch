import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from atlas.reasoning_engine import solve
from atlas.quality_checks import evaluate

class Result:
    def __init__(self, content): self.content = content

class MockLLM:
    def __init__(self, answers): self.answers = iter(answers); self.calls = []
    def chat(self, model, messages, **kwargs):
        self.calls.append((model, messages, kwargs))
        return Result(next(self.answers))

class ReasoningTests(unittest.TestCase):
    def test_three_calls_and_format_in_review(self):
        llm = MockLLM(['Anna > David > Ben > Clara', 'Anna > David > Ben > Clara', 'Anna > David > Ben > Clara'])
        result = solve(llm, 'test', [{'role':'user','content':'Nur Reihenfolge alt nach jung'}])
        self.assertEqual(result.calls, 3)
        self.assertEqual(result.answer, 'Anna > David > Ben > Clara')
        self.assertIn('Nur Reihenfolge', llm.calls[-1][1][-1]['content'])
        self.assertTrue(evaluate('only_order', result.answer)[0])
    def test_empty_draft_fails_closed(self):
        with self.assertRaises(ValueError):
            solve(MockLLM(['']), 'test', [{'role':'user','content':'Frage'}])
    def test_empty_final_fails_closed(self):
        with self.assertRaises(ValueError):
            solve(MockLLM(['a','b','']), 'test', [{'role':'user','content':'Frage'}])
    def test_contradiction_false_positive_rejected(self):
        self.assertFalse(evaluate('siblings_contradiction', 'Das ist ein Widerspruch, aber kein logischer Widerspruch.')[0])
    def test_cancelled_before_start(self):
        import threading
        stop = threading.Event(); stop.set()
        result = solve(MockLLM([]), 'test', [], stop=stop)
        self.assertEqual(result.calls, 0)

if __name__ == '__main__': unittest.main()
