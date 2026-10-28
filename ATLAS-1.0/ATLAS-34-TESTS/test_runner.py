import contextlib, importlib.util, io, json, pathlib, subprocess, sys, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('atlas_gesamt_test',ROOT/'atlas_gesamt_test.py')
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
class RunnerTests(unittest.TestCase):
 def test_catalog_unique_complete(self):
  self.assertEqual(len(mod.TASKS),102)
  self.assertEqual(len({t['id'] for t in mod.TASKS}),102)
  self.assertEqual(len({t['category'] for t in mod.TASKS}),34)
 def test_atomic_save_resume(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)/'state.json';obj={'model':'test','results':{'T001':{'status':'bestanden'}}};mod.save(p,obj)
   self.assertEqual(json.loads(p.read_text()),obj)
   self.assertFalse((pathlib.Path(d)/'state.json.tmp').exists())
 def test_unfinished_is_open(self):
  state={'model':'test','results':{'T001':{'status':'bestanden'}}}
  self.assertIn('OFFEN (1/3 geprüft)',mod.report(state))
 def test_manual_self_report_not_automatic_pass(self):
  state={'model':'test','results':{f'T{i:03}':{'status':'manuell bestätigt'} for i in range(1,4)}}
  self.assertIn('0.0/100',mod.report(state))
 def test_verify_without_ollama(self):
  with tempfile.TemporaryDirectory() as d:
   r=subprocess.run([sys.executable,str(ROOT/'atlas_gesamt_test.py'),'--verify','--state',str(pathlib.Path(d)/'state.json')],capture_output=True,text=True,timeout=10)
   self.assertEqual(r.returncode,0,r.stderr)
   self.assertIn('102 Aufgaben; 34 Kategorien',r.stdout)
if __name__=='__main__':unittest.main()
