"""Atlas: lokales Backend – Chat, Agent mit Werkzeugen, Gedächtnis, Lernen & Weiterentwicklung, Sprache."""
from .intents import plan
from . import agent as agent_mod
from . import llm
from .memory import MemoryIndex
from .learning import Learning
from .evolution import Evolution
from .tasks import TaskJournal
from .cloud import Cloud
from .tools import Environment, build_tools, fetch_webpage, search_web
import contextlib
import json
import math
import os
import secrets
import shutil
import socket
import sqlite3
import struct
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request
import uuid
import wave
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

ROOT = Path(__file__).resolve().parent.parent
DATA = Path(os.environ.get('ATLAS_DATA_DIR', str(Path.home()/'.atlas-ai')))
DB = DATA/'atlas.db'
MODEL = os.environ.get('ATLAS_MODEL', 'qwen3:4b')
MODELS = ('qwen3:4b', 'qwen3:8b')
OLLAMA = 'http://127.0.0.1:11434/api/chat'
PORT = int(os.environ.get('ATLAS_PORT', '8765'))
HTTP = urllib.request.build_opener(urllib.request.ProxyHandler({}))
SYSTEM = (ROOT/'personality.txt').read_text(encoding='utf-8')
VERSION = '1.0.3'
TOKEN = secrets.token_urlsafe(32)
LOCK = threading.RLock()
CHAT_LOCK = threading.Lock()
AUDIO_LOCK = threading.Lock()
SPEECH_LOCK = threading.RLock()
PENDING = {}
ACTIVE = {}
SPEECH = None
ALLOWED_APPS = {'finder':'Finder','calculator':'Calculator','notes':'Notes','calendar':'Calendar','safari':'Safari','textedit':'TextEdit'}
ALLOWED_FOLDERS = {'downloads':Path.home()/'Downloads','desktop':Path.home()/'Desktop','documents':Path.home()/'Documents'}

class BusyError(Exception): pass

def settings():
    """Optionale Nutzereinstellungen aus ~/.atlas-ai/settings.json (z. B. zusätzliche Ordner)."""
    try:return json.loads((DATA/'settings.json').read_text(encoding='utf-8'))
    except (OSError,ValueError):return {}

def save_settings(changes):
    """Einstellungen ergänzen (atomar), vorhandene Einträge bleiben erhalten."""
    with LOCK:
        merged={**settings(),**changes}
        DATA.mkdir(parents=True,exist_ok=True,mode=0o700)
        temp=DATA/'settings.json.neu'
        temp.write_text(json.dumps(merged,ensure_ascii=False,indent=2),encoding='utf-8')
        os.replace(temp,DATA/'settings.json')

_CLOUD=None
def cloud():
    global _CLOUD
    with LOCK:
        if _CLOUD is None:
            _CLOUD=Cloud(database,lambda:settings().get('cloud') or {},lambda value:save_settings({'cloud':value}))
        return _CLOUD

def allowed_roots():
    roots=[Path.home()]
    for raw in settings().get('allowed_roots',[]) if isinstance(settings().get('allowed_roots'),list) else []:
        path=Path(os.path.expanduser(str(raw)))
        if path.is_absolute() and path.is_dir() and str(path) not in ('/','/System','/usr','/bin','/etc'):roots.append(path)
    return roots

OLLAMA_CLIENT=llm.Ollama(opener=HTTP)
_LEARNING=None
def learning():
    global _LEARNING
    with LOCK:
        if _LEARNING is None:_LEARNING=Learning(database)
        return _LEARNING
def log(message):print(f'{stamp()} {message}',flush=True)
_ENV=None
def tool_env():
    global _ENV
    with LOCK:
        if _ENV is None:_ENV=Environment(roots=allowed_roots(),vision=OLLAMA_CLIENT.see)
        return _ENV
_EVOLUTION=None
def evolution():
    """Lernbausteine: Fähigkeiten, Wissen, Verbesserungen, Code-Werkstatt, Freigaben, Lernplaner."""
    global _EVOLUTION
    with LOCK:
        if _EVOLUTION is None:
            env=tool_env()
            _EVOLUTION=Evolution(database,learning(),OLLAMA_CLIENT,DATA,ROOT,
                                 search=lambda query:search_web(env,query,max_results=8).data.get('results',[]),
                                 fetch=lambda url:fetch_webpage(env,url,40000).output,
                                 busy=CHAT_LOCK.locked,log=log,
                                 # Lernaufträge: eigenes Modell möglich (z. B. qwen3:8b schreibt besseren Code)
                                 model=lambda:OLLAMA_CLIENT.agent_model(settings().get('skill_model') or settings().get('agent_model')))
        return _EVOLUTION
BRIDGE=agent_mod.Bridge()
_AGENT=None
def agent():
    global _AGENT
    with LOCK:
        if _AGENT is None:
            memory=MemoryIndex(database,embed=lambda model,texts:OLLAMA_CLIENT.embed(model,texts))
            env=tool_env()
            _AGENT=agent_mod.Agent(OLLAMA_CLIENT,build_tools(env),BRIDGE,memory,log=log,learning=learning(),
                                   journal=TaskJournal(database))
            _AGENT.evolution=evolution()
            _AGENT.cloud=cloud()
            _AGENT.dynamic_tools=lambda:evolution().tools(env)
        return _AGENT

def agent_request(obj):
    """Validate the native agent request (protocol 2)."""
    system=text_field(obj,'system',8000)
    rows=obj.get('history')
    if not isinstance(rows,list) or not 1<=len(rows)<=60:raise ValueError('Ein bis 60 Gesprächsbeiträge erwartet.')
    for row in rows:
        if not isinstance(row,dict) or row.get('role') not in ('user','assistant'):raise ValueError('Ungültige Gesprächsrolle.')
        text_field(row,'content',12000)
    if rows[-1]['role']!='user':raise ValueError('Die letzte Nachricht muss vom Nutzer stammen.')
    memories=obj.get('memories',[])
    if not isinstance(memories,list) or len(memories)>500 or not all(isinstance(m,str) and len(m)<=1000 for m in memories):
        raise ValueError('Ungültige Erinnerungen.')
    tools=obj.get('tools',[])
    if not isinstance(tools,list) or len(tools)>80 or not all(isinstance(t,dict) and isinstance(t.get('name'),str) for t in tools):
        raise ValueError('Ungültige Werkzeugliste.')
    model=obj.get('model')
    if model is not None and not llm.is_local_model(model):raise ValueError('Nur lokale Modelle sind erlaubt.')
    return agent_mod.Request(system=system,history=[{'role':r['role'],'content':r['content'].strip()} for r in rows],
                             memories=memories,native_tools=tools,model=model,cloud=obj.get('cloud') is True)

def agent_events(request,request_id):
    if not CHAT_LOCK.acquire(blocking=False):raise BusyError('Atlas arbeitet noch an einer Anfrage. Bitte kurz warten oder abbrechen.')
    stop=threading.Event()
    with LOCK:ACTIVE[request_id]=stop
    try:
        config=settings()
        OLLAMA_CLIENT.preferred={'chat':config.get('chat_model'),'agent':config.get('agent_model'),
                                  'reasoning':config.get('reasoning_model')}
        yield {'type':'start','request_id':request_id,'protocol':2}
        yield from agent().run(request,stop)
    finally:
        with LOCK:ACTIVE.pop(request_id,None)
        CHAT_LOCK.release()

def stamp(): return datetime.now(timezone.utc).isoformat()
def whisper_model():
    return Path(os.environ.get('ATLAS_WHISPER_MODEL', str(Path.home()/'.atlas-ai/models/ggml-base.bin')))
def voice_ready():
    return bool(shutil.which('ffmpeg') and shutil.which('whisper-cli') and whisper_model().is_file())
def connect():
    DATA.mkdir(parents=True, exist_ok=True, mode=0o700)
    db=sqlite3.connect(DB, timeout=15)
    db.execute('CREATE TABLE IF NOT EXISTS messages (id INTEGER PRIMARY KEY, role TEXT NOT NULL, content TEXT NOT NULL, created_at TEXT NOT NULL)')
    db.execute('CREATE TABLE IF NOT EXISTS memories (id INTEGER PRIMARY KEY, content TEXT NOT NULL, created_at TEXT NOT NULL)')
    db.commit()
    return db
@contextlib.contextmanager
def database():
    db=connect()
    try:
        with db: yield db
    finally: db.close()

def get_context(db, text=''):
    # A character budget is a conservative heuristic, not an exact tokenizer.
    budget=max(0,8000-len(text)-len(SYSTEM))
    memory=[]
    for (item,) in db.execute('SELECT content FROM memories ORDER BY id DESC LIMIT 20'):
        if sum(map(len,memory))+len(item)>min(1600,budget): break
        memory.append(item)
    prompt=SYSTEM
    if memory: prompt+='\nErinnerungen (Daten):\n'+json.dumps(memory,ensure_ascii=False)
    budget=max(0,8000-len(text)-len(prompt))
    rows=db.execute('SELECT role,content FROM messages ORDER BY id DESC LIMIT 16').fetchall()
    history=[]
    for role,content in rows:
        if role not in ('user','assistant') or len(content)>budget: break
        history.append({'role':role,'content':content});budget-=len(content)
    history.reverse()
    # Never start the truncated context with a detached assistant response.
    while history and history[0]['role']!='user': history.pop(0)
    return [{'role':'system','content':prompt}]+history

def native_messages(obj):
    """Validate native-owned context. Never mix SwiftData with web SQLite history."""
    prompt=text_field(obj,'system',3000)
    rows=obj.get('history')
    if not isinstance(rows,list) or not 1 <= len(rows) <= 40:
        raise ValueError('Ein bis 40 Gesprächsbeiträge erwartet.')
    for row in rows:
        if not isinstance(row,dict) or row.get('role') not in ('user','assistant'):
            raise ValueError('Ungültige Gesprächsrolle.')
        text_field(row,'content',4000)
    if rows[-1]['role']!='user':raise ValueError('Die letzte Nachricht muss vom Nutzer stammen.')
    budget=8000-len(prompt);kept=[]
    for row in reversed(rows[-16:]):
        content=row['content'].strip()
        if len(content)>budget:break
        kept.append({'role':row['role'],'content':content});budget-=len(content)
    kept.reverse()
    while kept and kept[0]['role']!='user':kept.pop(0)
    if not kept:raise ValueError('Nachricht passt nicht in den Kontext.')
    return [{'role':'system','content':prompt}]+kept

def selected_model(value):
    if not isinstance(value,str) or (value not in MODELS and value not in llm.INSTRUCT_MODELS):
        raise ValueError('Erlaubte Modelle: qwen3:4b und qwen3:8b.')
    return value

def fast_variant(model):
    """„qwen3:4b“ → schnelle 4B-Variante ohne Denkschritt, falls installiert."""
    if model=='qwen3:4b':
        names=OLLAMA_CLIENT._tags[1]   # nur zwischengespeicherte Liste – keine zusätzliche Anfrage
        for candidate in llm.INSTRUCT_MODELS:
            if candidate in names:return candidate
    return model

def ollama_request(messages, model, stream=True):
    return urllib.request.Request(OLLAMA, data=json.dumps({
        'model':selected_model(model),'messages':messages,'stream':stream,'think':False,
        'keep_alive':'15m','options':{'num_ctx':4096,'num_predict':512,'temperature':0.4}
    }).encode(), headers={'Content-Type':'application/json'})

def public_error(exc):
    if isinstance(exc,llm.ModelError):return str(exc)
    if isinstance(exc,urllib.error.HTTPError) and exc.code==404:
        return 'Modell fehlt in Ollama. Für 8B zuerst enable_quality.command ausführen.'
    if isinstance(exc,(TimeoutError,socket.timeout)):
        return 'Ollama antwortet zu lange nicht. Prüfe ollama ps und versuche den 4B-Modus.'
    return 'Lokale Verarbeitung fehlgeschlagen: '+str(exc)[:180]

ThinkFilter=llm.ThinkFilter

def chat_events(text, model=None, request_id=None, persist=True, native_context=None):
    model=selected_model(model or MODEL)
    if not CHAT_LOCK.acquire(blocking=False): raise BusyError('Atlas beantwortet noch eine Anfrage. Bitte kurz warten.')
    ident=request_id or uuid.uuid4().hex
    model=fast_variant(model)
    # Denk-Modelle schreiben ihr Selbstgespräch ohne öffnendes <think> – dann bis </think> verbergen
    # (Ergebnis der einmaligen Prüfung, sobald bekannt).
    filter_=ThinkFilter(start_hidden=OLLAMA_CLIENT._reasoning.get(model,False))
    stop=threading.Event();start=time.monotonic();first=None;answer='';finished=False;final={}
    with LOCK: ACTIVE[ident]=stop
    try:
        yield {'type':'start','request_id':ident,'model':model}
        if native_context is not None:
            messages=native_context
        else:
            with database() as db: messages=get_context(db,text)+[{'role':'user','content':text}]
        with HTTP.open(ollama_request(messages,model),timeout=60) as response:
            for raw in response:
                if stop.is_set():break
                if not raw.strip():continue
                part=json.loads(raw)
                if part.get('error'):raise RuntimeError(part['error'])
                delta=filter_.feed(part.get('message',{}).get('content',''))
                if delta:
                    if first is None:first=time.monotonic()-start
                    answer+=delta
                    yield {'type':'delta','text':delta}
                if part.get('done'):
                    tail=filter_.feed('',True)
                    if tail:
                        answer+=tail
                        if first is None:first=time.monotonic()-start
                        yield {'type':'delta','text':tail}
                    final=part;finished=True;break
        if stop.is_set():
            yield {'type':'cancelled','request_id':ident};return
        if not finished:raise RuntimeError('Ollama hat die Antwort unvollständig beendet.')
        if '</think>' in answer:answer=llm.strip_think(answer)   # Selbstgespräch eines Denk-Modells entfernen
        if not answer.strip():raise RuntimeError('Leere Modellantwort. Bitte erneut versuchen.')
        if persist:
            with database() as db:
                db.executemany('INSERT INTO messages(role,content,created_at) VALUES (?,?,?)',
                    [('user',text,stamp()),('assistant',answer.strip(),stamp())])
        duration=final.get('eval_duration',0)/1e9
        yield {'type':'done','answer':answer.strip(),'truncated':final.get('done_reason')=='length',
               'metrics':{'first_token_s':round(first or 0,2),'total_s':round(time.monotonic()-start,2),
                          'load_s':round(final.get('load_duration',0)/1e9,2),
                          'tokens_per_s':round(final.get('eval_count',0)/duration,1) if duration else None}}
    finally:
        with LOCK:ACTIVE.pop(ident,None)
        CHAT_LOCK.release()

def ask(text,model=None):
    for event in chat_events(text,model):
        if event['type']=='done':return event['answer']
    raise RuntimeError('Antwort abgebrochen.')

def allowed_action(kind,target):
    if not isinstance(kind,str) or not isinstance(target,str):return None
    if kind=='app' and target in ALLOWED_APPS:return ['open','-a',ALLOWED_APPS[target]]
    if kind=='folder' and target in ALLOWED_FOLDERS:return ['open',str(ALLOWED_FOLDERS[target])]
    return None

def transcribe(raw,language):
    if not voice_ready():raise ValueError('Lokale Spracherkennung fehlt: ffmpeg, whisper-cli und ggml-base.bin prüfen.')
    if language not in ('de','en','auto'):raise ValueError('Ungültige Aufnahmesprache.')
    if not raw:raise ValueError('Leere Aufnahme.')
    if not AUDIO_LOCK.acquire(blocking=False):raise BusyError('Eine Aufnahme wird bereits verarbeitet.')
    start=time.monotonic()
    try:
        with tempfile.TemporaryDirectory() as td:
            source=Path(td)/'input.audio';wav=Path(td)/'audio.wav';out=Path(td)/'transcript'
            source.write_bytes(raw)
            subprocess.run(['ffmpeg','-nostdin','-loglevel','error','-y','-i',str(source),'-t','30',
                            '-ar','16000','-ac','1','-c:a','pcm_s16le',str(wav)],check=True,timeout=20,capture_output=True)
            with wave.open(str(wav),'rb') as audio:
                count=audio.getnframes();samples=audio.readframes(count)
            rms=math.sqrt(sum(v[0]*v[0] for v in struct.iter_unpack('<h',samples))/max(1,count))
            if count<3200 or rms<65:
                return {'text':'','seconds':round(time.monotonic()-start,2),'message':'Keine deutliche Sprache erkannt. Bitte näher am Mikrofon sprechen.'}
            subprocess.run(['whisper-cli','-m',str(whisper_model()),'-f',str(wav),'-nt','-l',language,
                            '-t','4','-otxt','-of',str(out)],check=True,timeout=90,capture_output=True)
            text=Path(str(out)+'.txt').read_text(encoding='utf-8').strip()
            return {'text':text,'seconds':round(time.monotonic()-start,2)}
    finally:AUDIO_LOCK.release()

def stop_speech():
    global SPEECH
    with SPEECH_LOCK:
        if SPEECH is not None and SPEECH.poll() is None:
            SPEECH.terminate()
            try:SPEECH.wait(timeout=2)
            except subprocess.TimeoutExpired:SPEECH.kill();SPEECH.wait()
        SPEECH=None

def positive_id(obj,key='id'):
    value=obj.get(key)
    if type(value)!=int or value<1:raise ValueError('Ungültige ID.')
    return value

def cloud_route(action,obj):
    """Optionales Cloud-Modell: Status, Einstellungen, Schlüssel (nur in den macOS-Schlüsselbund)."""
    c=cloud()
    if action=='status':return c.status()
    if action=='settings':
        return c.update(**{k:v for k,v in obj.items() if k in ('enabled','model','monthly_limit_usd','always_allow','effort')})
    if action=='key':
        key=obj.get('key')
        if not isinstance(key,str) or len(key)>400:raise ValueError('Schlüssel fehlt.')
        try:c.keychain.set(key.strip())
        except Exception as exc:raise ValueError(str(exc)) from None
        return c.status()
    if action=='key/delete':
        c.keychain.delete();return c.status()
    raise ValueError('Unbekannte Cloud-Aktion.')

def learning_route(action,obj):
    """Bereich „Learning & Evolution“ der App. Nur mit Sitzungstoken erreichbar – das Sprachmodell
    selbst kann diese Schnittstelle nicht aufrufen (lokale Adressen sind für Werkzeuge gesperrt)."""
    evo=evolution()
    if action=='overview':return evo.overview()
    if action=='decide':
        if not isinstance(obj.get('approved'),bool):raise ValueError('approved fehlt.')
        return evo.decide(positive_id(obj),obj['approved'],obj.get('confirm_security') is True)
    if action=='rule':
        text=obj.get('text');active=obj.get('active');scope=obj.get('scope')
        if text is not None and not isinstance(text,str):raise ValueError('Ungültiger Text.')
        if active is not None and not isinstance(active,bool):raise ValueError('Ungültiger Status.')
        return {'ok':evo.learning.edit_rule(positive_id(obj),text=text,active=active,scope=scope)}
    if action=='fact':
        statement=obj.get('statement')
        if statement is not None and not isinstance(statement,str):raise ValueError('Ungültige Aussage.')
        return {'ok':evo.knowledge.edit_fact(positive_id(obj),statement=statement,status=obj.get('status'))}
    if action=='facts':return {'facts':evo.knowledge.facts(positive_id(obj))}
    if action=='delete':
        kind=obj.get('kind')
        if kind in ('experiences','rules'):return {'ok':evo.learning.delete(kind,positive_id(obj))}
        if kind in ('fact','topic'):return {'ok':evo.knowledge.delete(kind,positive_id(obj))}
        raise ValueError('Unbekannte Art.')
    if action=='confirm':
        if not isinstance(obj.get('good'),bool):raise ValueError('good fehlt.')
        evo.learning.confirm_experience(positive_id(obj),obj['good']);return {'ok':True}
    if action=='settings':
        changes={k:v for k,v in obj.items() if k in ('enabled','paused','max_minutes_per_day','allow_network','cycle_hours')}
        return evo.scheduler.update(**changes)
    if action=='job':
        kind=obj.get('kind')
        if kind=='skill':return {'job':evo.scheduler.submit('skill',{'description':text_field(obj,'text',300)})}
        if kind=='topic':return {'job':evo.scheduler.submit('topic',{'topic':text_field(obj,'text',200)})}
        if kind=='analyse':return {'job':evo.scheduler.submit('analyse',{})}
        raise ValueError('Unbekannte Auftragsart.')
    if action=='cancel':return {'ok':evo.scheduler.cancel(positive_id(obj))}
    if action=='skill':
        name=obj.get('name')
        if not isinstance(name,str) or len(name)>60:raise ValueError('Ungültiger Name.')
        if obj.get('do')=='rollback':return {'message':evo.skills.rollback(name)}
        if obj.get('do')=='disable':evo.skills.disable(name);return {'message':f'{name} deaktiviert.'}
        raise ValueError('Unbekannte Aktion.')
    if action=='hint/rollback':evo.improvement.rollback(positive_id(obj));return {'ok':True}
    if action=='code/rollback':return {'message':evo.workshop.rollback(positive_id(obj))}
    if action=='export':return {'examples':evo.learning.export_training_data()}
    raise ValueError('Unbekannte Lern-Aktion.')

def text_field(obj,key,limit):
    value=obj.get(key)
    if not isinstance(value,str) or not value.strip() or len(value)>limit:raise ValueError('Text fehlt oder ist zu lang.')
    return value.strip()

class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def setup(self):
        super().setup();self.connection.settimeout(90)
    def send_bytes(self,data,kind,status=200):
        self.send_response(status)
        self.send_header('Content-Type',kind);self.send_header('Cache-Control','no-store')
        self.send_header('X-Content-Type-Options','nosniff');self.send_header('X-Frame-Options','DENY')
        self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
    def send_json(self,obj,status=200):
        self.send_bytes(json.dumps(obj,ensure_ascii=False).encode(),'application/json; charset=utf-8',status)
    def trusted(self,write=False):
        expected=f'127.0.0.1:{self.server.server_port}'
        if self.headers.get('Host')!=expected:
            self.send_json({'error':'Ungültiger Host'},403);return False
        if self.headers.get('Origin') not in (None,'http://'+expected):
            self.send_json({'error':'Fremder Ursprung abgewiesen'},403);return False
        if self.headers.get('Sec-Fetch-Site')=='cross-site':
            self.send_json({'error':'Fremde Webseite abgewiesen'},403);return False
        if write and not secrets.compare_digest(self.headers.get('X-Atlas-Token',''),TOKEN):
            self.send_json({'error':'Sitzung abgelaufen. Seite neu laden.'},403);return False
        return True
    def do_GET(self):
        if not self.trusted():return
        path=urlparse(self.path).path
        if path=='/':return self.send_bytes((ROOT/'web/index.html').read_text().replace('__ATLAS_TOKEN__',TOKEN).encode(),'text/html; charset=utf-8')
        if path=='/app.js':return self.send_bytes((ROOT/'web/app.js').read_bytes(),'application/javascript; charset=utf-8')
        if path=='/api/native/session':
            return self.send_json({'protocol':1,'agent':2,'version':VERSION,'token':TOKEN})
        if path=='/api/state':
            with database() as db:
                messages=db.execute('SELECT role,content FROM messages ORDER BY id DESC LIMIT 50').fetchall()
                notes=db.execute('SELECT id,content FROM memories ORDER BY id DESC LIMIT 50').fetchall()
            return self.send_json({'version':VERSION,'model':MODEL,'models':MODELS,
                'messages':[{'role':r,'content':c} for r,c in reversed(messages)],
                'memories':[{'id':i,'content':c} for i,c in notes],'voice_ready':voice_ready()})
        if path=='/api/health':
            result={'voice_ready':voice_ready(),'ollama':False,'models':[]}
            try:
                with HTTP.open(OLLAMA_CLIENT.base+'/api/tags',timeout=3) as r:tags=json.load(r)
                names=[m['name'] for m in tags.get('models',[]) if llm.is_local_model(m.get('name',''))]
                result.update(ollama=True,models=[n for n in names if n in MODELS],installed=names)
            except Exception as exc:result['error']=public_error(exc)
            return self.send_json(result)
        self.send_json({'error':'Nicht gefunden'},404)
    def do_POST(self):
        if not self.trusted(True):return
        try:
            if self.headers.get('Transfer-Encoding'):raise ValueError('Transfer-Encoding nicht unterstützt.')
            length=int(self.headers.get('Content-Length','0'))
            if length<0:raise ValueError('Ungültige Länge.')
            if length>12*1024*1024:return self.send_json({'error':'Aufnahme/Anfrage zu groß.'},413)
            raw=self.rfile.read(length)
            if len(raw)!=length:raise ValueError('Unvollständige Anfrage.')
            parsed=urlparse(self.path);path=parsed.path
            if path=='/api/transcribe':
                language=parse_qs(parsed.query).get('language',['de'])[0]
                return self.send_json(transcribe(raw,language))
            obj=json.loads(raw)
            if not isinstance(obj,dict):raise ValueError('JSON-Objekt erwartet.')
            return self.route(path,obj)
        except BusyError as exc:self.send_json({'error':str(exc)},409)
        except (ValueError,UnicodeError) as exc:self.send_json({'error':str(exc)},400)
        except (BrokenPipeError,ConnectionResetError):pass
        except Exception as exc:self.send_json({'error':public_error(exc)},503)
    def route(self,path,obj):
        global SPEECH
        if path=='/api/native/agent/result':
            ident=obj.get('id')
            if not isinstance(ident,str) or len(ident)>80:raise ValueError('Ungültige ID.')
            content=obj.get('content','')
            if not isinstance(content,str) or len(content)>200000:raise ValueError('Ungültiges Ergebnis.')
            if not BRIDGE.resolve(ident,{'content':content,'isError':bool(obj.get('isError'))}):
                return self.send_json({'error':'Keine wartende Anfrage.'},404)
            return self.send_json({'ok':True})
        if path=='/api/native/agent/stream':
            request=agent_request(obj)
            ident=obj.get('request_id',uuid.uuid4().hex)
            if not isinstance(ident,str) or len(ident)>80:raise ValueError('Ungültige Anfrage-ID.')
            return self.stream_events(agent_events(request,ident))
        if path=='/api/native/intent':
            return self.send_json(plan(text_field(obj,'message',4000)))
        if path=='/api/native/memory/export':
            with database() as db:
                rows=db.execute('SELECT content,created_at FROM memories ORDER BY id LIMIT 10000').fetchall()
            def iso(value):
                return datetime.fromisoformat(value).astimezone(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
            return self.send_json({'version':1,'exportedAt':iso(stamp()),'device':'Atlas Web lokal',
                'entries':[{'content':c,'category':'Sonstiges','learned':False,'createdAt':iso(d),'updatedAt':iso(d)} for c,d in rows]})
        if path in ('/api/chat','/api/chat/stream','/api/native/chat/stream'):
            context=native_messages(obj) if path=='/api/native/chat/stream' else None
            text=context[-1]['content'] if context else text_field(obj,'message',4000)
            model=selected_model(obj.get('model',MODEL))
            if path=='/api/chat':return self.send_json({'answer':ask(text,model)})
            ident=obj.get('request_id',uuid.uuid4().hex)
            if not isinstance(ident,str) or len(ident)>80:raise ValueError('Ungültige Anfrage-ID.')
            return self.stream_events(chat_events(text,model,ident,persist=context is None,native_context=context))
        if path.startswith('/api/native/cloud/'):
            return self.send_json(cloud_route(path.removeprefix('/api/native/cloud/'),obj))
        if path.startswith('/api/native/learning/'):
            return self.send_json(learning_route(path.removeprefix('/api/native/learning/'),obj))
        return self.route_rest(path,obj)
    def stream_events(self,events):
        # Advance before headers, so a busy model returns an actual HTTP 409.
        first=next(events)
        try:
            self.send_response(200);self.send_header('Content-Type','application/x-ndjson; charset=utf-8')
            self.send_header('Cache-Control','no-store');self.send_header('X-Content-Type-Options','nosniff')
            self.send_header('Connection','close');self.end_headers();self.close_connection=True
            def emit(event):
                self.wfile.write((json.dumps(event,ensure_ascii=False)+'\n').encode());self.wfile.flush()
            emit(first)
            try:
                for event in events:emit(event)
            except (BrokenPipeError,ConnectionResetError):pass
            except Exception as exc:emit({'type':'error','error':public_error(exc)})
        finally:events.close()
    def route_rest(self,path,obj):
        global SPEECH
        if path=='/api/chat/cancel':
            ident=obj.get('request_id')
            if not isinstance(ident,str):raise ValueError('Ungültige Anfrage-ID.')
            with LOCK:
                if ident in ACTIVE:ACTIVE[ident].set()
            return self.send_json({'ok':True})
        if path=='/api/memory':
            value=text_field(obj,'content',1000)
            with database() as db:db.execute('INSERT INTO memories(content,created_at) VALUES (?,?)',(value,stamp()))
            return self.send_json({'ok':True})
        if path=='/api/memory/delete':
            ident=obj.get('id')
            if type(ident)!=int or ident<1:raise ValueError('Ungültige ID.')
            with database() as db:db.execute('DELETE FROM memories WHERE id=?',(ident,))
            return self.send_json({'ok':True})
        if path=='/api/clear':
            if not CHAT_LOCK.acquire(False):raise BusyError('Bitte zuerst die laufende Antwort beenden.')
            try:
                with database() as db:db.execute('DELETE FROM messages')
            finally:CHAT_LOCK.release()
            return self.send_json({'ok':True})
        if path=='/api/action/request':
            kind=obj.get('kind');target=obj.get('target')
            if not allowed_action(kind,target):return self.send_json({'error':'Aktion nicht erlaubt'},403)
            token=uuid.uuid4().hex
            with LOCK:PENDING.clear();PENDING[token]=(kind,target,time.monotonic())
            return self.send_json({'token':token,'description':f'{"Programm" if kind=="app" else "Ordner"} öffnen: {target}. Bitte bestätigen.'})
        if path=='/api/action/confirm':
            token=obj.get('token')
            if not isinstance(token,str):raise ValueError('Ungültiges Token.')
            with LOCK:action=PENDING.pop(token,None)
            if not action:raise ValueError('Keine gültige ausstehende Aktion.')
            if obj.get('approved') is not True:return self.send_json({'ok':True,'message':'Abgebrochen'})
            if time.monotonic()-action[2]>60:raise ValueError('Bestätigung abgelaufen.')
            subprocess.run(allowed_action(*action[:2]),check=True,timeout=10,capture_output=True)
            return self.send_json({'ok':True,'message':'Aktion ausgeführt'})
        if path=='/api/speak/stop':
            stop_speech();return self.send_json({'ok':True})
        if path=='/api/speak':
            text=text_field(obj,'text',6000)
            with SPEECH_LOCK:
                stop_speech()
                SPEECH=subprocess.Popen(['say','--',text],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            return self.send_json({'ok':True})
        return self.send_json({'error':'Nicht gefunden'},404)

def main():
    os.umask(0o077)
    if MODEL not in MODELS:raise SystemExit('ATLAS_MODEL muss qwen3:4b oder qwen3:8b sein.')
    connect().close()
    try:server=ThreadingHTTPServer(('127.0.0.1',PORT),Handler)
    except OSError as exc:raise SystemExit(f'Atlas kann Port {PORT} nicht öffnen: {exc}. Alte Atlas-Instanz mit Ctrl+C beenden.')
    print(f'ATLAS {VERSION} | http://127.0.0.1:{server.server_port} | {MODEL}',flush=True)
    print('Lokal. Beenden mit Ctrl+C.',flush=True)
    evolution().scheduler.start()
    try:server.serve_forever()
    except KeyboardInterrupt:pass
    finally:
        stop_speech();server.server_close()
        if _EVOLUTION:_EVOLUTION.scheduler.stop()
if __name__=='__main__':main()
