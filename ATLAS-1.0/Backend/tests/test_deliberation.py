import unittest
from atlas.deliberation import should_deliberate, answer

class FakeLLM:
    def __init__(self, answers):
        self.answers = iter(answers)
        self.calls = []
    def chat(self, model, messages, **kwargs):
        self.calls.append((model, messages, kwargs))
        return type('Reply', (), {'content': next(self.answers)})()

class DeliberationTests(unittest.TestCase):
    def test_complex_german(self):
        self.assertTrue(should_deliberate('Analysiere diese Hypothese'))
        self.assertTrue(should_deliberate('Vergleiche die beiden Theorien'))
    def test_simple_unchanged(self):
        self.assertFalse(should_deliberate('Hallo Atlas, wie geht es dir?'))
    def test_two_passes(self):
        llm = FakeLLM(['Entwurf', 'Korrigierte Antwort'])
        self.assertEqual(answer(llm, 'local', [{'role':'user','content':'Beweise X'}]), 'Korrigierte Antwort')
        self.assertEqual(len(llm.calls), 2)
        self.assertIn('Entwurf', str(llm.calls[1][1]))
    def test_no_false_success_for_empty(self):
        with self.assertRaises(ValueError):
            answer(FakeLLM(['']), 'local', [{'role':'user','content':'x'}])
    def test_cancel_before_call(self):
        class Stop:
            def is_set(self): return True
        llm = FakeLLM([])
        self.assertEqual(answer(llm, 'local', [], stop=Stop()), '')
        self.assertEqual(llm.calls, [])
