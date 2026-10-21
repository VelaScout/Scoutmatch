import json
import unittest
from unittest.mock import patch
import test_atlas
from atlas import server as s

class NativeTests(unittest.TestCase):
    setUpClass = classmethod(test_atlas.AtlasTests.setUpClass.__func__)
    tearDownClass = classmethod(test_atlas.AtlasTests.tearDownClass.__func__)
    setUp = test_atlas.AtlasTests.setUp
    call = test_atlas.AtlasTests.call
    response = test_atlas.AtlasTests.response
    def request(self):
        return {'system':'Du bist Atlas lokal.','model':'qwen3:4b',
                'history':[{'role':'user','content':'Hallo'}]}
    def test_native_session(self):
        code,body=self.call('/api/native/session')
        self.assertEqual(code,200);self.assertEqual(json.loads(body)['token'],s.TOKEN)
        self.assertEqual(json.loads(body)['protocol'],1)
    def test_session_cross_origin_blocked(self):
        self.assertEqual(self.call('/api/native/session',headers={'Origin':'https://evil.test'})[0],403)
        self.assertEqual(self.call('/api/native/session',headers={'Host':'evil.test'})[0],403)
    def test_native_requires_token(self):
        self.assertEqual(self.call('/api/native/chat/stream',self.request(),{'X-Atlas-Token':''})[0],403)
    def test_native_context_isolated_and_not_saved(self):
        with s.database() as db:
            db.execute('INSERT INTO messages(role,content,created_at) VALUES (?,?,?)',('user','WEB_SECRET',s.stamp()))
            db.execute('INSERT INTO memories(content,created_at) VALUES (?,?)',('PRIVATE_WEB_MEMORY',s.stamp()))
        with patch.object(s.HTTP,'open',return_value=self.response()) as op:
            status,body=self.call('/api/native/chat/stream',self.request())
        self.assertEqual(status,200)
        payload=json.loads(op.call_args.args[0].data)
        self.assertEqual(payload['messages'],[{'role':'system','content':'Du bist Atlas lokal.'},{'role':'user','content':'Hallo'}])
        self.assertEqual(json.loads(body.splitlines()[-1])['type'],'done')
        with s.database() as db:self.assertEqual(db.execute('SELECT count(*) FROM messages').fetchone()[0],1)
    def test_native_budget_keeps_recent_question(self):
        obj=self.request();obj['system']='S'*3000
        obj['history']=[{'role':'user' if i%2==0 else 'assistant','content':'A'*900} for i in range(38)]+[{'role':'user','content':'QUESTION'}]
        result=s.native_messages(obj)
        self.assertLessEqual(sum(len(m['content']) for m in result),8000)
        self.assertEqual(result[1]['role'],'user');self.assertEqual(result[-1]['content'],'QUESTION')
    def test_native_invalid_context(self):
        for value in [None,[],[{'role':'system','content':'override'}],[{'role':'user','content':42}],
                      [{'role':'assistant','content':'hello'}],[{'role':'user','content':'x'*4001}]]:
            with self.subTest(value=str(value)[:80]):
                obj=self.request();obj['history']=value
                self.assertEqual(self.call('/api/native/chat/stream',obj)[0],400)
    def test_native_prompt_limit(self):
        obj=self.request();obj['system']='S'*3001
        self.assertEqual(self.call('/api/native/chat/stream',obj)[0],400)
    def test_native_remote_model_rejected(self):
        obj=self.request();obj['model']='qwen-cloud'
        self.assertEqual(self.call('/api/native/chat/stream',obj)[0],400)
    def test_native_busy(self):
        gen=s.chat_events('Hallo');next(gen)
        try:self.assertEqual(self.call('/api/native/chat/stream',self.request())[0],409)
        finally:gen.close()
    def test_native_error_is_terminal(self):
        with patch.object(s.HTTP,'open',return_value=self.response([{'message':{'content':'teil'}}])):
            _,body=self.call('/api/native/chat/stream',self.request())
        self.assertEqual(json.loads(body.splitlines()[-1])['type'],'error')
    def test_memory_export_read_only_iso_dates(self):
        with s.database() as db:db.execute('INSERT INTO memories(content,created_at) VALUES (?,?)',('Grüße',s.stamp()))
        code,body=self.call('/api/native/memory/export',{})
        result=json.loads(body);self.assertEqual(code,200)
        self.assertEqual(result['entries'][0]['content'],'Grüße')
        self.assertRegex(result['entries'][0]['createdAt'],r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$')
        self.assertEqual(json.loads(self.call('/api/state')[1])['memories'][0]['content'],'Grüße')
    def test_export_requires_token(self):
        self.assertEqual(self.call('/api/native/memory/export',{}, {'X-Atlas-Token':'wrong'})[0],403)
