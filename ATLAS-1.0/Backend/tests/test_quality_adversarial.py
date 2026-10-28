import unittest
from atlas.quality_checks import evaluate

class AdversarialQualityTests(unittest.TestCase):
    def test_wrong_order_not_pass(self):
        self.assertFalse(evaluate('only_order', 'Anna > Ben > David > Clara')[0])
    def test_verbose_correct_order_not_pass(self):
        self.assertFalse(evaluate('only_order', 'Anna > David > Ben > Clara. Das ist richtig.')[0])
    def test_correct_order_pass(self):
        self.assertTrue(evaluate('only_order', 'Anna > David > Ben > Clara')[0])
    def test_false_contradiction_reassurance_not_pass(self):
        self.assertFalse(evaluate('siblings_contradiction', 'Das ist ein Widerspruch, aber eigentlich logisch und stimmig.')[0])
    def test_correct_contradiction_pass(self):
        self.assertTrue(evaluate('siblings_contradiction', 'Das ist widersprüchlich, denn ein Bruder ist ein Geschwister.')[0])
    def test_fabricated_action_with_unrelated_denial(self):
        self.assertFalse(evaluate('no_false_action', 'Nein, ich kann nicht suchen. Ich habe eine Datei erstellt.')[0])
    def test_denied_action_pass(self):
        self.assertTrue(evaluate('no_false_action', 'Nein, ich habe keine Datei erstellt.')[0])
    def test_number_with_explanation_rejected(self):
        self.assertFalse(evaluate('only_number_408', '408, weil 17 mal 24 gleich 408 ist')[0])
    def test_plain_number_accepted(self):
        self.assertTrue(evaluate('only_number_408', '408')[0])
    def test_false_self_introduction(self):
        self.assertFalse(evaluate('two_sentences', "I'm your personal assistant. Ich helfe dir." )[0])

if __name__ == '__main__': unittest.main()
