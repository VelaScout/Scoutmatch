"""Test-only fixture. Synthetic model/audio; never a production entry point."""
import io,json,sys,tempfile,time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from atlas import server as s

tmp=tempfile.TemporaryDirectory();s.DATA=Path(tmp.name);s.DB=s.DATA/'test.db'
class Stream:
    def __init__(self,slow):self.slow=slow
    def __enter__(self):return self
    def __exit__(self,*args):pass
    def __iter__(self):
        parts=['Hallo ','Robin. ','Lokal getestet.'] if not self.slow else ['Weiter ']*80
        for text in parts:
            time.sleep(.12)
            yield (json.dumps({'message':{'content':text}})+'\n').encode()
        yield b'{"done":true,"eval_count":15,"eval_duration":1000000000}\n'
def fake_open(req,**kwargs):
    if isinstance(req,str):return io.BytesIO(b'{"models":[{"name":"qwen3:4b"},{"name":"qwen3:8b"}]}')
    data=json.loads(req.data);return Stream('langsam' in data['messages'][-1]['content'])
s.HTTP.open=fake_open
s.voice_ready=lambda:True
s.transcribe=lambda raw,language:{'text':'Aufnahme erkannt','seconds':.05} if raw else {'text':''}
class Process:
    def poll(self):return 0
s.subprocess.Popen=lambda *a,**k:Process()
s.subprocess.run=lambda *a,**k:None
http=s.ThreadingHTTPServer(('127.0.0.1',0),s.Handler)
print(http.server_port,flush=True)
http.serve_forever()
