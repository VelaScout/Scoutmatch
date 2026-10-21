"""Local diagnostics and a transparent, limited quality/latency benchmark."""
import argparse
import json
import platform
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from . import server as s

CASES=[
 ('rechnung','Was ist 17 mal 23? Antworte nur mit der Zahl.',lambda a:a.strip().rstrip('.')=='391'),
 ('anweisung','Antworte exakt mit: Atlas bereit.',lambda a:a.strip()=='Atlas bereit.'),
 ('kontext','Wie heißt die Testperson, die ich dir genannt habe? Antworte nur mit ihrem Vornamen.',lambda a:a.strip().rstrip('.')=='Mira'),
 ('erklaerung','Erkläre in höchstens zwei Sätzen, warum der Himmel blau erscheint.',None),
 ('faehigkeiten','Kannst du gerade meinen Mac-Bildschirm sehen? Antworte kurz und ehrlich.',None),
 ('englisch','Explain in one English sentence what a local AI model is.',None),
]

def benchmark(models):
    results=[];old_data,old_db=s.DATA,s.DB
    try:
        with tempfile.TemporaryDirectory() as td:
            s.DATA=Path(td);s.DB=s.DATA/'benchmark.db'
            with s.database() as db:db.execute('INSERT INTO memories(content,created_at) VALUES (?,?)',('Die Testperson heißt Mira.',s.stamp()))
            for model in models:
                for i,(name,prompt,check) in enumerate(CASES,1):
                    print(f'[{model} {i}/{len(CASES)}] {name} …',flush=True)
                    item={'model':model,'case':name,'prompt':prompt,'answer':'','automatic_check':None}
                    try:
                        for event in s.chat_events(prompt,model,persist=False):
                            if event['type']=='done':
                                item.update(answer=event['answer'],metrics=event['metrics'],truncated=event['truncated'])
                        item['automatic_check']=check(item['answer']) if check else None
                        if not item['answer']:raise RuntimeError('Keine vollständige Antwort')
                        print('  '+str(item.get('metrics',{})),flush=True)
                    except Exception as exc:item['error']=s.public_error(exc);print('  FEHLER '+item['error'],flush=True)
                    results.append(item)
    finally:s.DATA,s.DB=old_data,old_db
    return results

def audio_roundtrip():
    # Synthetic voice -> file -> real decoder -> real Whisper. No microphone access.
    with tempfile.TemporaryDirectory() as td:
        path=Path(td)/'sample.aiff';phrase='Hallo Atlas. Heute testen wir die lokale Spracherkennung.'
        subprocess.run(['say','-o',str(path),'--',phrase],check=True,timeout=30,capture_output=True)
        result=s.transcribe(path.read_bytes(),'de')
        return {'source':'macOS say, synthetisch; kein Mikrofontest','expected':phrase,'recognized':result['text'],
                'seconds':result['seconds'],'nonempty':bool(result['text'])}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--core',action='store_true')
    parser.add_argument('--benchmark',action='store_true');parser.add_argument('--compare',action='store_true')
    parser.add_argument('--audio',action='store_true');parser.add_argument('--output')
    args=parser.parse_args();checks=[];failed=False
    def check(name,ok,required=True):
        nonlocal failed
        print(('OK    ' if ok else 'FEHLT ')+name,flush=True)
        checks.append({'check':name,'ok':bool(ok),'required':required})
        if required and not ok:failed=True
    check('macOS Apple Silicon',platform.system()=='Darwin' and platform.machine()=='arm64')
    check('Python >= 3.10',sys.version_info>=(3,10))
    if not args.core:
        for tool in ('say','open','ffmpeg','whisper-cli'):check(tool,bool(shutil.which(tool)))
        check('Whisper-Modell',s.whisper_model().is_file())
    models=[]
    try:
        with s.HTTP.open('http://127.0.0.1:11434/api/tags',timeout=5) as r:
            models=[m['name'] for m in json.load(r).get('models',[]) if m['name'] in s.MODELS]
        check('Ollama und Modell '+s.MODEL,s.MODEL in models)
    except Exception as exc:check('Ollama: '+s.public_error(exc),False)
    report={'version':s.VERSION,'created_at':datetime.now().astimezone().isoformat(),'platform':platform.system(),
            'architecture':platform.machine(),'python':platform.python_version(),'checks':checks,
            'scope':'Reale lokale Modelltests mit synthetischen Fragen; kein umfassender Qualitätsnachweis.'}
    try:
        report['ollama_ps']=subprocess.run(['ollama','ps'],capture_output=True,text=True,timeout=5).stdout.strip()
    except (OSError,subprocess.SubprocessError):report['ollama_ps']='Nicht verfügbar'
    if args.benchmark and models:
        chosen=models if args.compare else [s.MODEL] if s.MODEL in models else []
        report['benchmark']=benchmark(chosen)
        if any(x.get('error') or x.get('automatic_check') is False for x in report['benchmark']):failed=True
    if args.audio:
        try:
            report['audio']=audio_roundtrip()
            if not report['audio']['nonempty']:failed=True
            print('Audio-Test erkannt: '+report['audio']['recognized'],flush=True)
        except Exception as exc:report['audio']={'error':str(exc)};failed=True
    if args.output:
        out=Path(args.output).expanduser();out.parent.mkdir(parents=True,exist_ok=True)
        out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        print('Diagnose gespeichert: '+str(out),flush=True)
    print('Offen: Safari, echtes Mikrofon, hörbare Stimme, alle App-Ziele und inhaltliche Bewertung.',flush=True)
    return 1 if failed else 0
if __name__=='__main__':sys.exit(main())
