import unittest
from atlas.answer_guard import requested_format, conforms
from atlas.reasoning_engine import solve

class FakeLLM:
    def __init__(self, outputs):
        self.outputs = iter(outputs)
        self.calls = []
    def chat(self, model, messages, **kwargs):
        self.calls.append((messages, kwargs))
        return type('Reply', (), {'content': next(self.outputs)})()

class AnswerGuardTests(unittest.TestCase):
    def test_detect_number(self):
        self.assertEqual(requested_format('Was ist 17 mal 24? Nur die Zahl.'), 'number')
        self.assertEqual(requested_format('Only the number'), 'number')
    def test_detect_order(self):
        self.assertEqual(requested_format('Nur die Reihenfolge'), 'order')
    def test_detect_word(self):
        self.assertEqual(requested_format('Antworte mit genau einem Wort'), 'word')
    def test_no_false_format(self):
        self.assertIsNone(requested_format('Erkläre mir das ausführlich'))
    def test_strict_number(self):
        self.assertTrue(conforms('number', '408'))
        self.assertFalse(conforms('number', '408, denn 17 mal 24 ist 408'))
    def test_strict_order(self):
        self.assertTrue(conforms('order', 'Anna > David > Ben > Clara'))
        self.assertFalse(conforms('order', 'Reihenfolge: Anna, David, Ben, Clara'))
    def test_word(self):
        self.assertTrue(conforms('word', 'Paris'))
        self.assertFalse(conforms('word', 'Die Antwort ist Paris'))
    def test_retry_bad_format(self):
        llm = FakeLLM(['408', '408', '408, weil ...', '408'])
        result = solve(llm, 'test', [{'role':'user','content':'17 mal 24? Nur die Zahl.'}])
        self.assertEqual(result.answer, '408')
        self.assertEqual(result.calls, 4)
    def test_no_retry_good_format(self):
        llm = FakeLLM(['408', '408', '408'])
        result = solve(llm, 'test', [{'role':'user','content':'17 mal 24? Nur die Zahl.'}])
        self.assertEqual(result.calls, 3)
    def test_no_retry_unconstrained(self):
        llm = FakeLLM(['Antwort A', 'Antwort B', 'Eine ausführliche Antwort'])
        result = solve(llm, 'test', [{'role':'user','content':'Erkläre das.'}])
        self.assertEqual(result.calls, 3)
    def test_no_false_success_after_failed_retry(self):
        llm = FakeLLM(['408', '408', 'Antwort 408', 'Leider ist es 408'])
        result = solve(llm, 'test', [{'role':'user','content':'Nur die Zahl.'}])
        self.assertFalse(conforms('number', result.answer))
        self.assertEqual(result.calls, 4)

if __name__ == '__main__':
    unittest.main()
