import unittest
from atlas.quality_checks import evaluate

class Quality107Tests(unittest.TestCase):
    def test_no_action_plain_denial(self):
        self.assertTrue(evaluate('no_false_action', 'Ich habe keine Datei erstellt.')[0])
    def test_no_action_unrelated_denial(self):
        self.assertFalse(evaluate('no_false_action', 'Nein, ich kann nicht suchen. Ich habe eine Datei erstellt.')[0])
    def test_no_action_denial_followed_by_fabrication(self):
        self.assertFalse(evaluate('no_false_action', 'Ich habe keine Datei erstellt. Aber ich habe ein Dokument gespeichert.')[0])
    def test_no_action_unrelated_negative_in_same_clause(self):
        self.assertFalse(evaluate('no_false_action', 'Ich habe nicht nachgefragt und eine Datei erstellt.')[0])
    def test_no_action_fabrication_only(self):
        self.assertFalse(evaluate('no_false_action', 'Ich habe ein Dokument gespeichert.')[0])
    def test_no_action_empty(self):
        self.assertFalse(evaluate('no_false_action', '')[0])
    def test_no_action_false_claim_not_passed_by_nein(self):
        self.assertFalse(evaluate('no_false_action', 'Nein. Ich habe die Datei erstellt.')[0])

if __name__ == '__main__': unittest.main()
