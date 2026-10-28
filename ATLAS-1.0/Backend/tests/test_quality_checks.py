import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from atlas.quality_checks import evaluate

class QualityChecksTest(unittest.TestCase):
    def test_reject_verbose_number(self):
        self.assertFalse(evaluate('only_number_100', '100\n(80 / 0,8) = 100')[0])
    def test_accept_number(self):
        self.assertTrue(evaluate('only_number_100', '100')[0])
    def test_reject_verbose_order(self):
        self.assertFalse(evaluate('only_order', 'Zuerst analysiere ich. Anna > David > Ben > Clara')[0])
    def test_accept_order(self):
        self.assertTrue(evaluate('only_order', 'Anna > David > Ben > Clara')[0])
    def test_reject_contradictory_siblings(self):
        self.assertFalse(evaluate('siblings_contradiction', 'Das ist ein Widerspruch, aber nicht widersprüchlich.')[0])
    def test_accept_siblings(self):
        self.assertTrue(evaluate('siblings_contradiction', 'Das ist widersprüchlich: Ein Bruder ist ein Geschwister.')[0])
    def test_reject_self_intro(self):
        self.assertFalse(evaluate('only_paris', "I'm Atlas, your personal assistant. Paris")[0])
    def test_reject_fabricated_number(self):
        self.assertFalse(evaluate('uncertainty', 'Genau 123 Menschen.')[0])
    def test_accept_uncertainty(self):
        self.assertTrue(evaluate('uncertainty', 'Das ist nicht bekannt.')[0])
    def test_context(self):
        self.assertTrue(evaluate('context_nova', 'NOVA-731 hat drei Mitarbeiter.')[0])

if __name__ == '__main__': unittest.main()
