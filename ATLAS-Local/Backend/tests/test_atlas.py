import contextlib
import http.client
import io
import json
import math
import os
import socket
import struct
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
import wave
from pathlib import Path
from unittest.mock import MagicMock, patch
from atlas import server as s

class AtlasTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp=tempfile.TemporaryDirectory();s.DATA=Path(cls.tmp.name);s.DB=s.DATA/'atlas.db'
        cls.http=s.ThreadingHTTPServer(('127.0.0.1',0),s.Handler)
        cls.thread=threading.Thread(target=cls.http.serve_forever,daemon=True);cls.thread.start()
        cls.base='http://127.0.0.1:'+str(cls.http.server_port)
    @classmethod
    def tearDownClass(cls):
        cls.http.shutdown();cls.http.server_close();cls.thread.join();cls.tmp.cleanup()
    def setUp(self):
        with s.database() as db:db.execute('DELETE FROM messages');db.execute('DELETE FROM memories')
        s.PENDING.clear();s.SPEECH=None
    def call(self,path,data=None,headers=None,raw=None):
        h={'X-Atlas-Token':s.TOKEN};h.update(headers or {})
        req=urllib.request.Request(self.base+path,data=(raw if raw is not None else json.dumps(data).encode()) if data is not None or raw is not None else None,headers=h)
        try:
            with urllib.request.urlopen(req,timeout=5) as r:return r.status,r.read()
        except urllib.error.HTTPError as e:
            with e:return e.code,e.read()
    def state(self):return json.loads(self.call('/api/state')[1])
    def response(self,parts=None):
        parts=parts if parts is not None else [
          {'message':{'content':'Hallo '},'done':False},
          {'message':{'content':'Robin'},'done':False},
          {'done':True,'eval_count':5,'eval_duration':1000000000,'load_duration':300000000}]
        return io.BytesIO(b''.join((json.dumps(p)+'\n').encode() for p in parts))
    def test_ui_token(self):
        code,body=self.call('/');self.assertEqual(code,200);self.assertIn(s.TOKEN.encode(),body)
    def test_javascript_served(self):self.assertIn(b'/api/chat/stream',self.call('/app.js')[1])
    def test_state(self):self.assertEqual(self.state()['version'],'0.2.3')
    def test_unknown(self):self.assertEqual(self.call('/missing')[0],404)
    def test_unknown_post(self):self.assertEqual(self.call('/missing',{})[0],404)
    def test_origin(self):self.assertEqual(self.call('/api/clear',{}, {'Origin':'https://evil.test'})[0],403)
    def test_token(self):self.assertEqual(self.call('/api/clear',{}, {'X-Atlas-Token':'wrong'})[0],403)
    def test_host(self):self.assertEqual(self.call('/api/state',headers={'Host':'evil.test'})[0],403)
    def test_cross_site(self):self.assertEqual(self.call('/',headers={'Sec-Fetch-Site':'cross-site'})[0],403)
    def test_same_origin(self):self.assertEqual(self.call('/api/clear',{}, {'Origin':self.base})[0],200)
    def test_bad_json(self):self.assertEqual(self.call('/api/chat',raw=b'{')[0],400)
    def test_array_json(self):self.assertEqual(self.call('/api/chat',[])[0],400)
    def test_non_text_message(self):self.assertEqual(self.call('/api/chat',{'message':{}})[0],400)
    def test_empty_chat(self):self.assertEqual(self.call('/api/chat',{'message':''})[0],400)
    def test_long_chat(self):self.assertEqual(self.call('/api/chat',{'message':'x'*4001})[0],400)
    def test_remote_model_denied(self):self.assertEqual(self.call('/api/chat',{'message':'Hallo','model':'some-cloud'})[0],400)
    def test_invalid_length(self):
        conn=http.client.HTTPConnection('127.0.0.1',self.http.server_port,timeout=2)
        conn.request('POST','/api/chat',headers={'X-Atlas-Token':s.TOKEN,'Content-Length':'-1'})
        with conn.getresponse() as r:self.assertEqual(r.status,400)
        conn.close()
    def test_large_body_rejected_before_read(self):
        conn=http.client.HTTPConnection('127.0.0.1',self.http.server_port,timeout=2)
        conn.request('POST','/api/chat',headers={'X-Atlas-Token':s.TOKEN,'Content-Length':str(13*1024*1024)})
        with conn.getresponse() as r:self.assertEqual(r.status,413)
        conn.close()
    def test_memory_lifecycle(self):
        value="Robin's <script>Test</script>"
        self.assertEqual(self.call('/api/memory',{'content':value})[0],200)
        saved=self.state()['memories'][0];self.assertEqual(saved['content'],value)
        self.assertEqual(self.call('/api/memory/delete',{'id':saved['id']})[0],200)
        self.assertEqual(self.state()['memories'],[])
    def test_invalid_memory_id(self):self.assertEqual(self.call('/api/memory/delete',{'id':True})[0],400)
    def test_clear_preserves_memories(self):
        self.call('/api/memory',{'content':'Behalten'})
        with s.database() as db:db.execute('INSERT INTO messages(role,content,created_at) VALUES (?,?,?)',('user','Test',s.stamp()))
        self.call('/api/clear',{});state=self.state();self.assertEqual(state['messages'],[]);self.assertEqual(len(state['memories']),1)
    def test_context_budget(self):
        with s.database() as db:
            for i in range(20):db.execute('INSERT INTO messages(role,content,created_at) VALUES (?,?,?)',('user' if i%2==0 else 'assistant','A'*900,s.stamp()))
            messages=s.get_context(db,'B'*4000)
        self.assertLessEqual(sum(len(m['content']) for m in messages)+4000,8000)
        if len(messages)>1:self.assertEqual(messages[1]['role'],'user')
    def test_think_filter_chunk_boundary(self):
        f=s.ThinkFilter();out=''.join(f.feed(x) for x in ['<thi','nk>secret</thi','nk>Hallo']);out+=f.feed('',True)
        self.assertEqual(out,'Hallo')
    def test_stream_contract_and_persistence(self):
        with patch.object(s.HTTP,'open',return_value=self.response()) as op:
            code,body=self.call('/api/chat/stream',{'message':'Hallo'})
        self.assertEqual(code,200);events=[json.loads(x) for x in body.splitlines()]
        self.assertEqual([e['type'] for e in events],['start','delta','delta','done'])
        self.assertEqual(events[-1]['answer'],'Hallo Robin');self.assertEqual(events[-1]['metrics']['tokens_per_s'],5)
        payload=json.loads(op.call_args.args[0].data);self.assertTrue(payload['stream']);self.assertFalse(payload['think'])
        self.assertEqual(payload['options']['num_ctx'],4096);self.assertEqual(len(self.state()['messages']),2)
    def test_stream_real_time_delivery(self):
        gate=threading.Event();first_delivered=threading.Event()
        class Delayed:
            def __enter__(self):return self
            def __exit__(self,*args):pass
            def __iter__(self):
                yield b'{"message":{"content":"Hallo"}}\n'
                first_delivered.set();gate.wait(3)
                yield b'{"done":true}\n'
        try:
            with patch.object(s.HTTP,'open',return_value=Delayed()):
                req=urllib.request.Request(self.base+'/api/chat/stream',data=b'{"message":"Hallo"}',headers={'X-Atlas-Token':s.TOKEN})
                with urllib.request.urlopen(req,timeout=4) as r:
                    self.assertEqual(json.loads(r.readline())['type'],'start')
                    self.assertEqual(json.loads(r.readline())['text'],'Hallo')
                    self.assertTrue(first_delivered.wait(1));self.assertFalse(gate.is_set());gate.set()
                    self.assertEqual(json.loads(r.readline())['type'],'done')
        finally:gate.set()
    def test_stream_incomplete_not_saved(self):
        with patch.object(s.HTTP,'open',return_value=self.response([{'message':{'content':'Teil'}}])):
            events=[json.loads(x) for x in self.call('/api/chat/stream',{'message':'Hallo'})[1].splitlines()]
        self.assertEqual(events[-1]['type'],'error');self.assertEqual(self.state()['messages'],[])
    def test_empty_model_answer_not_saved(self):
        with patch.object(s.HTTP,'open',return_value=self.response([{'done':True}])):
            self.assertEqual(self.call('/api/chat',{'message':'Hallo'})[0],503)
        self.assertEqual(self.state()['messages'],[])
    def test_thinking_not_exposed(self):
        with patch.object(s.HTTP,'open',return_value=self.response([{'message':{'thinking':'secret','content':'Hi'}},{'done':True}])):
            body=self.call('/api/chat/stream',{'message':'Hallo'})[1]
        self.assertNotIn(b'secret',body)
    def test_truncated_flag(self):
        with patch.object(s.HTTP,'open',return_value=self.response([{'message':{'content':'Hi'},'done':True,'done_reason':'length'}])):
            events=[json.loads(x) for x in self.call('/api/chat/stream',{'message':'Hallo'})[1].splitlines()]
        self.assertTrue(events[-1]['truncated'])
    def test_cancel_stops_without_save(self):
        with patch.object(s.HTTP,'open',return_value=self.response()):
            gen=s.chat_events('Hallo',request_id='test-cancel');next(gen);next(gen)
            self.assertEqual(self.call('/api/chat/cancel',{'request_id':'test-cancel'})[0],200)
            remaining=list(gen)
        self.assertEqual(remaining[-1]['type'],'cancelled');self.assertEqual(self.state()['messages'],[])
    def test_busy_and_clear_during_chat(self):
        gen=s.chat_events('Hallo');next(gen)
        try:
            self.assertEqual(self.call('/api/chat/stream',{'message':'Hallo'})[0],409)
            self.assertEqual(self.call('/api/clear',{})[0],409)
            self.assertEqual(self.call('/api/state')[0],200)
        finally:gen.close()
        self.assertFalse(s.CHAT_LOCK.locked());self.assertEqual(s.ACTIVE,{})
    def test_legacy_chat_endpoint(self):
        with patch.object(s.HTTP,'open',return_value=self.response()):
            code,body=self.call('/api/chat',{'message':'Hallo'})
        self.assertEqual(code,200);self.assertEqual(json.loads(body)['answer'],'Hallo Robin')
    def test_ollama_failure(self):
        with patch.object(s.HTTP,'open',side_effect=OSError('offline')):
            self.assertEqual(self.call('/api/chat',{'message':'Hallo'})[0],503)
    def test_health_failure(self):
        with patch.object(s.HTTP,'open',side_effect=OSError('offline')):
            state=json.loads(self.call('/api/health')[1]);self.assertFalse(state['ollama'])
    def test_allowlist_all_targets(self):
        for target in s.ALLOWED_APPS:self.assertEqual(s.allowed_action('app',target),['open','-a',s.ALLOWED_APPS[target]])
        for target in s.ALLOWED_FOLDERS:self.assertEqual(s.allowed_action('folder',target),['open',str(s.ALLOWED_FOLDERS[target])])
    def test_injection_denied(self):
        self.assertIsNone(s.allowed_action('app','Safari; rm -rf ~'));self.assertIsNone(s.allowed_action('app',[]))
        self.assertEqual(self.call('/api/action/request',{'kind':'shell','target':'ls'})[0],403)
    def action(self):return json.loads(self.call('/api/action/request',{'kind':'app','target':'finder'})[1])['token']
    def test_action_confirm_replay(self):
        token=self.action()
        with patch.object(s.subprocess,'run') as run:
            self.assertEqual(self.call('/api/action/confirm',{'token':token,'approved':True})[0],200)
            run.assert_called_once_with(['open','-a','Finder'],check=True,timeout=10,capture_output=True)
        self.assertEqual(self.call('/api/action/confirm',{'token':token,'approved':True})[0],400)
    def test_action_cancel(self):
        with patch.object(s.subprocess,'run') as run:
            self.call('/api/action/confirm',{'token':self.action(),'approved':False});run.assert_not_called()
    def test_action_expiry(self):
        token=self.action();s.PENDING[token]=('app','finder',time.monotonic()-61)
        self.assertEqual(self.call('/api/action/confirm',{'token':token,'approved':True})[0],400)
    def test_speak(self):
        with patch.object(s.subprocess,'Popen') as run:
            self.assertEqual(self.call('/api/speak',{'text':'Hallo'})[0],200)
            self.assertEqual(run.call_args.args[0],['say','--','Hallo'])
    def test_speak_replaces_own_process(self):
        process=MagicMock();process.poll.return_value=None;s.SPEECH=process
        self.assertEqual(self.call('/api/speak/stop',{})[0],200)
        process.terminate.assert_called_once();self.assertIsNone(s.SPEECH)
    def test_speak_missing_binary(self):
        with patch.object(s.subprocess,'Popen',side_effect=FileNotFoundError('say')):
            self.assertEqual(self.call('/api/speak',{'text':'Hallo'})[0],503)
    def test_transcribe_missing(self):
        with patch.object(s,'voice_ready',return_value=False):self.assertEqual(self.call('/api/transcribe',raw=b'audio')[0],400)
    def fake_audio(self,cmd,**kwargs):
        if cmd[0]=='ffmpeg':
            with wave.open(cmd[-1],'wb') as wav:
                wav.setnchannels(1);wav.setsampwidth(2);wav.setframerate(16000)
                wav.writeframes(b''.join(struct.pack('<h',int(1000*math.sin(i/15))) for i in range(8000)))
        else:Path(cmd[-1]+'.txt').write_text('Hallo Atlas',encoding='utf-8')
    def test_transcribe_pipeline_text_file(self):
        with patch.object(s,'voice_ready',return_value=True),patch.object(s.subprocess,'run',side_effect=self.fake_audio) as run:
            code,body=self.call('/api/transcribe?language=de',raw=b'audio')
        self.assertEqual(code,200);self.assertEqual(json.loads(body)['text'],'Hallo Atlas');self.assertEqual(run.call_count,2)
        self.assertIn('-otxt',run.call_args.args[0])
    def test_silence_skips_whisper(self):
        def silence(cmd,**kwargs):
            with wave.open(cmd[-1],'wb') as wav:
                wav.setnchannels(1);wav.setsampwidth(2);wav.setframerate(16000);wav.writeframes(b'\x00'*16000)
        with patch.object(s,'voice_ready',return_value=True),patch.object(s.subprocess,'run',side_effect=silence) as run:
            code,body=self.call('/api/transcribe',raw=b'audio')
        self.assertEqual(code,200);self.assertEqual(json.loads(body)['text'],'');self.assertEqual(run.call_count,1)
    def test_transcribe_language_rejected(self):
        with patch.object(s,'voice_ready',return_value=True):self.assertEqual(self.call('/api/transcribe?language=evil',raw=b'audio')[0],400)
    def test_transcribe_timeout_releases_lock(self):
        with patch.object(s,'voice_ready',return_value=True),patch.object(s.subprocess,'run',side_effect=s.subprocess.TimeoutExpired('ffmpeg',20)):
            self.assertEqual(self.call('/api/transcribe',raw=b'audio')[0],503)
        self.assertFalse(s.AUDIO_LOCK.locked())
    def test_transcribe_busy(self):
        s.AUDIO_LOCK.acquire()
        try:
            with patch.object(s,'voice_ready',return_value=True):self.assertEqual(self.call('/api/transcribe',raw=b'audio')[0],409)
        finally:s.AUDIO_LOCK.release()

if __name__=='__main__':unittest.main()
