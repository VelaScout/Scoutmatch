import json
import unittest
from unittest.mock import patch
import test_atlas
from atlas import server as s
from atlas.intents import plan, calculate, TARGETS

class IntentTests(unittest.TestCase):
    def test_arithmetic_table(self):
        for text,expected in [('Was ist 17 mal 23?','391.'),('0,1 plus 0,2','0,3.'),
                ('Berechne (2+3)*4','20.'),('What is 6 times 7?','42.'),
                ('10 geteilt durch 4','2,5.'),('-5+2','-3.'),('1/3','Ungefähr 0,333333.'),
                ('999999*999999','999998000001.')]:
            with self.subTest(text=text):self.assertEqual(plan(text),{'kind':'answer','answer':expected})
    def test_native_date_prefix(self):
        self.assertEqual(plan('[Kontext: Mittwoch Uhr, Zeitzone Europe/Berlin]\nWas ist 17 mal 23?')['answer'],'391.')
    def test_no_code_evaluation(self):
        for value in ["__import__('os').system('whoami')",'2**999999','1<<100','1/0','float(1)','[1,2]','1e1000','9'*161,'1+'*30+'1']:
            with self.subTest(value=value):self.assertIsNone(calculate(value))
    def test_no_explanation_hijack(self):
        for value in ['Erkläre wie man 17 mal 23 rechnet','Ist 1+1 wirklich 2?','Schreibe 1+2 in eine Datei']:
            self.assertEqual(plan(value)['kind'],'chat')
    def test_all_allowed_targets(self):
        for name,(kind,target) in TARGETS.items():
            self.assertEqual(plan('Öffne '+name)['steps'],[{'name':'local_open','input':{'kind':kind,'target':target}}])
    def test_two_step_task(self):
        steps=plan('Öffne Rechner und Notizen')['steps']
        self.assertEqual([x['input']['target'] for x in steps],['calculator','notes'])
    def test_three_step_and_dedup(self):
        self.assertEqual(len(plan('Öffne Finder, Rechner und Notizen')['steps']),3)
        self.assertEqual(len(plan('Öffne Finder und Finder')['steps']),1)
    def test_ambiguous_negated_or_injected_commands(self):
        for value in ['Öffne nicht Safari','Öffne Safari und lösche Dateien','Öffne /etc/passwd',
                      'Öffne Rechner; rm -rf ~','Kannst du Safari öffnen?',
                      'Öffne Finder und Rechner und Notizen und Safari','Er sagte: Öffne Rechner']:
            with self.subTest(value=value):self.assertEqual(plan(value)['kind'],'chat')
    def test_explicit_memory(self):
        self.assertEqual(plan('Merk dir: Ich trinke Tee')['steps'][0],{'name':'remember','input':{'content':'Ich trinke Tee','category':'Sonstiges'}})
        self.assertEqual(plan('Er sagte merk dir meine PIN')['kind'],'chat')
        self.assertEqual(plan('Merk dir '+'x'*1001)['kind'],'chat')
    def test_memory_query(self):
        self.assertEqual(plan('Was weißt du über mich?')['steps'][0]['name'],'list_memories')
    def test_ordinary_chat(self):
        self.assertEqual(plan('Was kann ich heute lernen?'),{'kind':'chat'})

class IntentHTTPTests(unittest.TestCase):
    setUpClass=classmethod(test_atlas.AtlasTests.setUpClass.__func__)
    tearDownClass=classmethod(test_atlas.AtlasTests.tearDownClass.__func__)
    setUp=test_atlas.AtlasTests.setUp
    call=test_atlas.AtlasTests.call
    def test_calculator_needs_no_ollama(self):
        with patch.object(s.HTTP,'open',side_effect=AssertionError('No model for arithmetic')):
            code,body=self.call('/api/native/intent',{'message':'17 mal 23'})
        self.assertEqual(code,200);self.assertEqual(json.loads(body)['answer'],'391.')
    def test_plan_does_not_execute(self):
        with patch.object(s.subprocess,'run') as run:
            code,body=self.call('/api/native/intent',{'message':'Öffne Rechner und Notizen'})
        self.assertEqual(code,200);self.assertEqual(len(json.loads(body)['steps']),2);run.assert_not_called()
        self.assertEqual(s.PENDING,{})
    def test_auth_and_origin(self):
        self.assertEqual(self.call('/api/native/intent',{'message':'17*23'},{'X-Atlas-Token':'wrong'})[0],403)
        self.assertEqual(self.call('/api/native/intent',{'message':'17*23'},{'Origin':'https://evil.test'})[0],403)
    def test_bad_input(self):
        for value in ['',{},'x'*4001]:self.assertEqual(self.call('/api/native/intent',{'message':value})[0],400)
    def test_multi_step_confirmed_execution(self):
        _,body=self.call('/api/native/intent',{'message':'Öffne Rechner und Notizen'})
        with patch.object(s.subprocess,'run') as run:
            for step in json.loads(body)['steps']:
                code,body=self.call('/api/action/request',step['input'])
                self.assertEqual(code,200)
                code,_=self.call('/api/action/confirm',{'token':json.loads(body)['token'],'approved':True})
                self.assertEqual(code,200)
            self.assertEqual([x.args[0] for x in run.call_args_list],[['open','-a','Calculator'],['open','-a','Notes']])
