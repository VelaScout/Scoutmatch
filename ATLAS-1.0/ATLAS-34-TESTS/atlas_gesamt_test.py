#!/usr/bin/env python3
"""ATLAS 34-Kategorien-Test. Lokale Ollama-Fragen plus manuelle Evidenzprüfungen."""
import argparse, datetime, hashlib, json, os, pathlib, re, time, urllib.request, urllib.parse
BASE=pathlib.Path(__file__).resolve().parent
TASKS=json.loads((BASE/'aufgaben.json').read_text(encoding='utf-8'))
FINGERPRINT=hashlib.sha256((BASE/'aufgaben.json').read_bytes()).hexdigest()
def local_ollama_url(url):
 parsed=urllib.parse.urlparse(url)
 return parsed.scheme=='http' and parsed.hostname in ('localhost','127.0.0.1','::1') and parsed.username is None and parsed.password is None and parsed.path in ('','/') and parsed.query=='' and parsed.fragment==''
def normalize(v):
 v=re.sub(r'<think>.*?</think>','',str(v),flags=re.I|re.S).strip().lower()
 return re.sub(r'\s+',' ',v.strip(' `\t\r\n.!')).replace(',','.')
def equivalent_answer(answer, expected):
 """Accept equivalent numeric notation, but not a different numeric result.

 Text answers stay strict. This intentionally does not grade semantic synonyms.
 """
 if normalize(answer)==normalize(expected): return True
 exp=normalize(expected)
 if not re.fullmatch(r"[+-]?(?:\d+(?:\.\d+)?|\d+/\d+)",exp): return False
 raw=str(answer).strip()
 # TeX fractions and ordinary fractions have the same mathematical meaning.
 raw=re.sub(r"\\(?:dfrac|tfrac|frac)\s*\{\s*(\d+)\s*\}\s*\{\s*(\d+)\s*\}",r"\1/\2",raw)
 # Only accept a complete short answer, a final equation result, or a
 # clearly marked last line of a worked solution. Never search for an
 # expected number anywhere in a response.
 lines=[line.strip() for line in raw.splitlines() if line.strip()]
 if not lines: return False
 last=lines[-1]
 if len(lines)>1 and len(last)>100: return False
 last=re.sub(r"^(?:rest|ergebnis|antwort|lösung|gesamt|schnitt|durchschnittsgeschwindigkeit)\s*:\s*", "",last,flags=re.I)
 last=re.sub(r"^\s*(?:x\s*=|=)\s*", "",last,flags=re.I)
 last=re.sub(r"^.*?=\s*", "",last) if '=' in last else last
 if '≈' in last: last=last.rsplit('≈',1)[-1].strip()
 last=re.sub(r"\s*(?:cm²|cm2|km/h|€|euro|stück)\s*$", "",last,flags=re.I)
 last=re.sub(r"\s*[.!]\s*$", "",last).strip().replace(',','.')
 # A final approximation sign may appear in the result.
 last=re.sub(r"^[≈~]\s*", "",last)
 if not re.fullmatch(r"[+-]?(?:\d+(?:\.\d+)?|\d+/\d+)",last): return False
 from fractions import Fraction
 try:
  actual=Fraction(last); target=Fraction(exp)
  # decimal expected values (e.g. 57.14) are rounded to stated precision
  if '.' in exp:
   return round(float(actual),len(exp.split('.')[1]))==float(target)
  return actual==target
 except (ValueError,ZeroDivisionError,OverflowError): return False

def rescore(state):
 """Regrade saved automatic answers without querying Ollama or erasing evidence."""
 changes=[]
 for t in TASKS:
  r=state.get('results',{}).get(t['id'])
  if not r or t['kind']!='auto' or r.get('kind')!='auto' or r.get('error'): continue
  new='bestanden' if equivalent_answer(r.get('answer',''),t['expected']) else 'fehlgeschlagen'
  if new!=r.get('status'):
   changes.append((t['id'],r.get('status'),new))
   r['previous_status']=r.get('status')
   r['status']=new
 return changes

def save(path, obj):
 path.parent.mkdir(parents=True,exist_ok=True)
 tmp=path.with_name(path.name+'.tmp'); tmp.write_text(json.dumps(obj,ensure_ascii=False,indent=2),encoding='utf-8'); os.replace(tmp,path)
def report(state):
 results=state['results']; categories=list(dict.fromkeys(t['category'] for t in TASKS))
 lines=['ATLAS – 34 Kategorien / 102 Aufgaben','Modell: '+state['model'],'Status: nicht absolvierte Aufgaben zählen NICHT als bestanden.','']
 for cat in categories:
  tasks=[t for t in TASKS if t['category']==cat]
  done=[results[t['id']] for t in tasks if t['id'] in results]
  passed=sum(r['status']=='bestanden' for r in done)
  complete=len(done)==len(tasks)
  score=round(100*passed/len(tasks),1) if complete else None
  status=(f'{score:.1f}/100' if complete else f'OFFEN ({len(done)}/{len(tasks)} geprüft)')
  lines.append(f'{cat}: {status} – {passed}/{len(tasks)} bestanden')
 lines+=['','Manuell bestätigte Aufgaben zählen ohne unabhängige Verifikation nicht als automatisch bestanden.', '95/100 je Kategorie erfordert bei 3 Aufgaben 3/3 unabhängig bestandene Prüfungen.',
         'Manuelle Prüfungen sind NICHT automatisch verifiziert. Ergebnisse mit Evidenz nachprüfen.',
         'Keine wissenschaftlich validierte ChatGPT/Claude-Gleichwertigkeit.']
 return '\n'.join(lines)+'\n'
def main():
 p=argparse.ArgumentParser()
 p.add_argument('--model',default='qwen3:4b-instruct-2507-q4_K_M')
 p.add_argument('--url',default='http://127.0.0.1:11434')
 p.add_argument('--timeout',type=int,default=75)
 p.add_argument('--limit',type=int,default=5,help='Neue automatische Fragen je Durchlauf; 0 = alle')
 p.add_argument('--manual',action='store_true',help='Manuelle Tests mit Belegen bewerten')
 p.add_argument('--retry-failed',action='store_true')
 p.add_argument('--rescore',action='store_true',help='Gespeicherte automatische Antworten erneut bewerten, ohne Ollama')
 p.add_argument('--verify',action='store_true',help='Prüft Testkatalog und bisherigen Ergebnisstand ohne Ollama')
 p.add_argument('--state',default=str(pathlib.Path.home()/'Downloads'/'ATLAS-Testberichte'/'atlas-34-kategorien.json'))
 a=p.parse_args()
 if a.limit<0 or a.timeout<1: p.error('Ungültige Parameter')
 if not local_ollama_url(a.url): p.error('Nur lokale Ollama-Adressen erlaubt; kein externer Server.')
 ids=[t.get('id') for t in TASKS]
 if len(ids)!=len(set(ids)) or any(t.get('kind') not in ('auto','manual') or not t.get('category') or not t.get('prompt') or not t.get('expected') for t in TASKS): p.error('Testkatalog ungültig')
 path=pathlib.Path(a.state).expanduser()
 state=json.loads(path.read_text(encoding='utf-8')) if path.exists() else {'version':1,'fingerprint':FINGERPRINT,'model':a.model,'results':{},'created':datetime.datetime.now().isoformat()}
 if state.get('fingerprint')!=FINGERPRINT or state.get('model')!=a.model: p.error('Ergebnisse gehören zu anderer Testversion oder Modell. Nutze neuen --state Pfad.')
 if any(k not in ids for k in state.get('results',{})): p.error('Unbekannte Test-ID in Ergebnisdatei')
 if a.rescore:
  changes=rescore(state)
  save(path,state)
  output=path.with_suffix('.txt'); output.write_text(report(state),encoding='utf-8')
  print('Neu bewertet:',len(changes),'geänderte Ergebnisse')
  for tid,old,new in changes: print(tid,old,'->',new)
  print(report(state)); return 0
 if a.verify:
  print('Katalog:',len(TASKS),'Aufgaben;',len(set(t['category'] for t in TASKS)),'Kategorien')
  print('Bereits abgeschlossen:',len(state['results']))
  print(report(state)); return 0
 if a.manual:
  for t in TASKS:
   if t['kind']!='manual' or (t['id'] in state['results'] and not a.retry_failed): continue
   print('\n'+t['id']+' '+t['category']+'\nAUFGABE: '+t['prompt']+'\nKRITERIUM: '+t['expected'])
   try: result=input('Ergebnis [b=bestanden/f=fehlgeschlagen/s=überspringen/q=Ende]: ').strip().lower()
   except (EOFError,KeyboardInterrupt): break
   if result=='q': break
   if result not in ('b','f'): continue
   evidence=input('Beleg (Dateipfad/Lognotiz, keine Passwörter): ').strip()
   if not evidence:
    print('Ohne Beleg wird nicht bewertet.'); continue
   state['results'][t['id']]={'status':'manuell bestätigt' if result=='b' else 'fehlgeschlagen','kind':'manual','evidence':evidence,'timestamp':datetime.datetime.now().isoformat()}
   save(path,state)
 else:
  todo=[t for t in TASKS if t['kind']=='auto' and (t['id'] not in state['results'] or (a.retry_failed and state['results'][t['id']]['status']!='bestanden'))]
  if todo:
   try:
    with urllib.request.urlopen(a.url.rstrip('/')+'/api/tags',timeout=8) as r: models=[m.get('name') for m in json.load(r).get('models',[])]
    if a.model not in models: raise RuntimeError('Modell nicht installiert: '+a.model)
   except Exception as e:
    print('Ollama nicht bereit:',e); return 2
  for t in todo[:a.limit or None]:
   print(t['id'],t['category'],flush=True); started=time.monotonic()
   try:
    data=json.dumps({'model':a.model,'stream':False,'messages':[{'role':'system','content':'Antworte ausschließlich mit der geforderten Kurzantwort.'},{'role':'user','content':t['prompt']}],'options':{'temperature':0,'num_predict':128}}).encode()
    req=urllib.request.Request(a.url.rstrip('/')+'/api/chat',data=data,headers={'Content-Type':'application/json'})
    with urllib.request.urlopen(req,timeout=a.timeout) as r: answer=json.load(r).get('message',{}).get('content','')
    error=None
   except Exception as e: answer='';error=str(e)
   status='bestanden' if error is None and equivalent_answer(answer,t['expected']) else 'fehlgeschlagen'
   state['results'][t['id']]={'status':status,'kind':'auto','answer':answer,'expected':t['expected'],'error':error,'seconds':round(time.monotonic()-started,2),'timestamp':datetime.datetime.now().isoformat()}
   save(path,state)
   print('  '+status+' ('+str(state['results'][t['id']]['seconds'])+'s)',flush=True)
 output=path.with_suffix('.txt'); output.parent.mkdir(parents=True,exist_ok=True); output.write_text(report(state),encoding='utf-8')
 print('\n'+report(state)); print('Ergebnisse:',path,'\nBericht:',output)
 return 0
if __name__=='__main__': raise SystemExit(main())
