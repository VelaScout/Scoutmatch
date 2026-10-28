import unittest
from atlas.intelligence_benchmark import QUESTIONS, CHALLENGES, normalize

class ChallengeTests(unittest.TestCase):
    def test_size(self):
        self.assertEqual(len(QUESTIONS), 18)
        self.assertEqual(len(CHALLENGES), 10)
    def test_unique_prompts(self):
        prompts = [x[1] for x in QUESTIONS + CHALLENGES]
        self.assertEqual(len(prompts), len(set(prompts)))
    def test_answers_nonempty(self):
        self.assertTrue(all(normalize(x[2]) for x in CHALLENGES))
