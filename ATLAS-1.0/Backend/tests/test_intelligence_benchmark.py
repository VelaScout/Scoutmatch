import unittest
from unittest.mock import patch
from atlas.intelligence_benchmark import QUESTIONS, assess, normalize, ollama_models

class IntelligenceBenchmarkTests(unittest.TestCase):
    def test_more_diverse_questions(self):
        self.assertGreaterEqual(len(QUESTIONS), 18)
        self.assertGreaterEqual(len(set(x[0] for x in QUESTIONS)), 6)
    def test_unreachable_ollama_not_passed(self):
        with patch('atlas.intelligence_benchmark.urllib.request.urlopen', side_effect=OSError('offline')):
            result = assess('fake')
        self.assertEqual(result['passed'], 0)
        self.assertEqual(result['attempted'], 0)
    def test_thinking_tags(self):
        self.assertEqual(normalize('<think>work</think> 42.'), '42')
    def test_different_wrong_answer(self):
        self.assertNotEqual(normalize('42'), normalize('43'))
