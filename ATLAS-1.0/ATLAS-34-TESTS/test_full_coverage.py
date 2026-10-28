"""Offline 102-case coverage audit; model results are NOT simulated as real AI performance."""
import importlib.util, json, pathlib, tempfile, unittest, unittest.mock, sys, io, contextlib
ROOT=pathlib.Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('atlas_test_under_audit',ROOT/'atlas_gesamt_test.py')
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
class CatalogAudit(unittest.TestCase):
 def test_each_case_has_valid_schema_and_nontrivial_content(self):
  for t in mod.TASKS:
   with self.subTest(id=t['id']):
    self.assertRegex(t['id'],r'^T\d{3}$')
    self.assertIn(t['kind'],('auto','manual'))
    self.assertTrue(t['category'].strip())
    self.assertGreater(len(t['prompt'].strip()),18)
    self.assertTrue(t['expected'].strip())
 def test_every_category_has_three_tests(self):
  from collections import Counter
  self.assertEqual(set(Counter(t['category'] for t in mod.TASKS).values()),{3})
 def test_all_manual_cases_are_not_automatically_passed(self):
  for t in (x for x in mod.TASKS if x['kind']=='manual'):
   with self.subTest(id=t['id']):
    state={'model':'test','results':{t['id']:{'status':'manuell bestätigt','evidence':'self report'}}}
    self.assertIn('OFFEN',mod.report(state))
 def test_all_auto_cases_require_actual_result(self):
  for t in (x for x in mod.TASKS if x['kind']=='auto'):
   with self.subTest(id=t['id']):
    state={'model':'test','results':{t['id']:{'status':'fehlgeschlagen'}}}
    self.assertNotIn(f'{t["category"]}: 100.0/100',mod.report(state))
 def test_all_34_categories_full_pass_score_is_100_not_95(self):
  state={'model':'test','results':{t['id']:{'status':'bestanden'} for t in mod.TASKS}}
  for cat in set(t['category'] for t in mod.TASKS):
   self.assertIn(f'{cat}: 100.0/100',mod.report(state))
 def test_incomplete_category_never_scores_95(self):
  state={'model':'test','results':{mod.TASKS[0]['id']:{'status':'bestanden'},mod.TASKS[1]['id']:{'status':'bestanden'}}}
  self.assertIn('OFFEN (2/3 geprüft)',mod.report(state))
 def test_atomic_persistence_across_interrupt(self):
  with tempfile.TemporaryDirectory() as d:
   path=pathlib.Path(d)/'progress.json'; obj={'results':{mod.TASKS[0]['id']:{'status':'bestanden'}}}
   mod.save(path,obj);self.assertEqual(json.loads(path.read_text()),obj)
   self.assertFalse(path.with_name('progress.json.tmp').exists())
 def test_ollama_endpoint_is_local_only(self):
  for url in ('http://127.0.0.1:11434','http://localhost:11434','http://[::1]:11434'):
   self.assertTrue(mod.local_ollama_url(url))
  for url in ('https://example.com','http://192.168.1.8:11434','http://127.0.0.1.evil.test','file:///etc/passwd','http://127.0.0.1:11434/api/chat','http://user:password@localhost:11434'):
   self.assertFalse(mod.local_ollama_url(url))
 def test_model_and_catalog_fingerprints_are_present(self):
  self.assertEqual(len(mod.FINGERPRINT),64)
  self.assertEqual(len(mod.TASKS),102)
if __name__=='__main__': unittest.main(verbosity=2)
