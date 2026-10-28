import contextlib
import io
import json
import math
import shutil
import struct
import subprocess
import tempfile
import unittest
import wave
from pathlib import Path
from unittest.mock import patch
from atlas import server as s
from atlas import doctor

class DiagnosticsTests(unittest.TestCase):
    def test_benchmark_isolates_database_and_restores_paths(self):
        previous_data,previous_db=s.DATA,s.DB
        def response(req,**kwargs):
            text=json.loads(req.data)['messages'][-1]['content']
            if '17 mal' in text:answer='391'
            elif 'exakt' in text:answer='Atlas bereit.'
            elif 'Testperson' in text:answer='Mira'
            else:answer='Kurze Testantwort.'
            return io.BytesIO((json.dumps({'message':{'content':answer},'done':True})+'\n').encode())
        with patch.object(s.HTTP,'open',side_effect=response),contextlib.redirect_stdout(io.StringIO()):
            result=doctor.benchmark(['qwen3:4b'])
        self.assertEqual(len(result),6)
        self.assertTrue(all(x['automatic_check'] for x in result[:3]))
        self.assertIs(s.DATA,previous_data);self.assertIs(s.DB,previous_db)
    def test_benchmark_reports_errors(self):
        with patch.object(s.HTTP,'open',side_effect=OSError('offline')),contextlib.redirect_stdout(io.StringIO()):
            result=doctor.benchmark(['qwen3:4b'])
        self.assertTrue(all(x.get('error') for x in result))
    def test_default_whisper_path(self):
        with patch.dict(s.os.environ,{},clear=True):
            self.assertEqual(s.whisper_model(),Path.home()/'.atlas-ai/models/ggml-base.bin')
    def test_missing_stream_releases_chat_lock(self):
        with patch.object(s.HTTP,'open',side_effect=OSError('offline')):
            with self.assertRaises(OSError):list(s.chat_events('Hallo',persist=False))
        self.assertFalse(s.CHAT_LOCK.locked())

@unittest.skipUnless(shutil.which('ffmpeg'),'ffmpeg nicht installiert: echte Codec-Tests übersprungen')
class CodecTests(unittest.TestCase):
    def roundtrip(self,extension,codec):
        original_run=subprocess.run
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);wav=root/'original.wav';encoded=root/('encoded.'+extension)
            with wave.open(str(wav),'wb') as f:
                f.setnchannels(1);f.setsampwidth(2);f.setframerate(16000)
                f.writeframes(b''.join(struct.pack('<h',int(2000*math.sin(i/12))) for i in range(16000)))
            original_run(['ffmpeg','-nostdin','-loglevel','error','-y','-i',str(wav),'-c:a',codec,str(encoded)],check=True,capture_output=True,timeout=10)
            def intercept(cmd,**kwargs):
                if cmd[0]=='whisper-cli':
                    with wave.open(cmd[cmd.index('-f')+1],'rb') as f:
                        self.assertEqual(f.getframerate(),16000);self.assertEqual(f.getnchannels(),1)
                        self.assertEqual(f.getsampwidth(),2);self.assertGreater(f.getnframes(),1000)
                    Path(cmd[-1]+'.txt').write_text('Codec getestet')
                    return subprocess.CompletedProcess(cmd,0)
                return original_run(cmd,**kwargs)
            with patch.object(s,'voice_ready',return_value=True),patch.object(s.subprocess,'run',side_effect=intercept):
                result=s.transcribe(encoded.read_bytes(),'de')
            self.assertEqual(result['text'],'Codec getestet')
    def test_real_mp4_aac_decode(self):self.roundtrip('mp4','aac')
    def test_real_webm_opus_decode(self):self.roundtrip('webm','libopus')

if __name__=='__main__':unittest.main()
