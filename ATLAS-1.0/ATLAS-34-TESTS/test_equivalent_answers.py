import importlib.util, pathlib, unittest
p=pathlib.Path(__file__).with_name('atlas_gesamt_test.py')
spec=importlib.util.spec_from_file_location('atlas_gesamt_test',p)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class EquivalentTests(unittest.TestCase):
 def test_exact_text(self):
  self.assertTrue(m.equivalent_answer('Ja','ja'))
  self.assertFalse(m.equivalent_answer('das','den'))
  self.assertFalse(m.equivalent_answer('Dankeschön','vielen dank'))
 def test_numeric_equivalences(self):
  for answer,expected in [('x = 9','9'),('150 cm²','150'),('\\frac{1}{6}','1/6'),('\\frac{7}{8}','7/8'),('\\frac{1}{2}','1/2'),('57,14 km/h','57.14'),('7x - 11 = 3x + 25\n4x = 36\nx = 9','9')]:
   with self.subTest(answer=answer): self.assertTrue(m.equivalent_answer(answer.replace('\\\\\\\\','\\\\'),expected))
 def test_wrong_numbers_rejected(self):
  for answer,expected in [('6','11'),('250€','240'),('48','96'),('108','120'),('3','5'),('48','24'),('64','50'),('60','150'),('1/3','1/6'),('Die Antwort ist 9, nicht 5','9')]:
   with self.subTest(answer=answer): self.assertFalse(m.equivalent_answer(answer,expected))
 def test_rescore_keeps_old_status(self):
  state={'results':{'T007':{'kind':'auto','status':'fehlgeschlagen','answer':'x = 9','error':None},'T009':{'kind':'auto','status':'fehlgeschlagen','answer':'250€','error':None}}}
  changes=m.rescore(state)
  self.assertEqual(len(changes),1)
  self.assertEqual(state['results']['T007']['previous_status'],'fehlgeschlagen')
  self.assertEqual(state['results']['T009']['status'],'fehlgeschlagen')
if __name__=='__main__': unittest.main()
