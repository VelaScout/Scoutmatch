"""Read-only live quality benchmark through the ATLAS native endpoint.

Unlike historical regex-only tests, failed requests are BLOCKED, never PASS.
The benchmark deliberately evaluates the final answer, not merely keyword hits.
"""
from __future__ import annotations
import datetime
import json
import pathlib
import sys
import time
import urllib.error
import urllib.request

from .quality_checks import evaluate
from .benchmark_summary import summarize

BASE = 'http://127.0.0.1:8765'
SYSTEM = ('Du bist ATLAS, ein hilfreicher Assistent auf einem Mac. Antworte in der Sprache des Nutzers. '
          'Antworte direkt, ohne Begrüßung oder ungefragte Selbstvorstellung. '
          'Halte explizite Formate strikt ein. Behaupte keine ausgeführten Aktionen ohne bestätigte Werkzeuge. '
          'Prüfe logische Aussagen auf Widersprüche. Gib Unsicherheit zu.')

CASES = [
 ('only_number_408', 'Was ist 17 mal 24? Nur die Zahl.', []),
 ('only_number_100', 'Nach 20 Prozent Rabatt kostet etwas 80 Euro. Ursprünglicher Preis? Nur Zahl.', []),
 ('only_paris', 'Antworte mit genau einem Wort: Hauptstadt von Frankreich?', []),
 ('only_order', 'Anna ist älter als Ben. Ben ist älter als Clara. David ist jünger als Anna, aber älter als Ben. Nur die Reihenfolge alt nach jung.', []),
 ('siblings_contradiction', 'Ich habe keine Geschwister. Mein Bruder ist 25. Was fällt dir auf?', []),
 ('uncertainty', 'Wie viele Menschen denken exakt jetzt an einen blauen Elefanten? Antworte kurz.', []),
 ('english_one_sentence', 'Explain gravity in English in exactly one sentence.', []),
 ('two_sentences', 'Was kannst du für mich tun? Antworte in genau zwei Sätzen.', []),
 ('context_nova', 'Wie heißt mein Projekt und wie viele Mitarbeiter hat es?', [
     {'role':'user','content':'Mein erfundenes Projekt heißt NOVA-731 und hat drei Mitarbeiter.'},
     {'role':'assistant','content':'Verstanden.'}]),
 ('no_false_action', 'Hast du gerade eine Datei auf meinem Mac erstellt? In diesem Gespräch wurde kein Werkzeug verwendet.', []),
]


def request_json(path, payload=None, token=None, timeout=8):
    headers={'Content-Type':'application/json'}
    if token: headers['X-Atlas-Token']=token
    req=urllib.request.Request(BASE+path, data=json.dumps(payload).encode('utf-8') if payload is not None else None,
                               headers=headers, method='POST' if payload is not None else 'GET')
    return urllib.request.urlopen(req, timeout=timeout)


def run_case(case, model, token):
    case_id, question, previous=case
    history=previous+[{'role':'user','content':question}]
    start=time.monotonic(); pieces=[]; done=None; errors=[]; first=None
    try:
        with request_json('/api/native/chat/stream',{'system':SYSTEM,'history':history,'model':model},token,100) as response:
            for raw in response:
                if not raw.strip(): continue
                event=json.loads(raw)
                kind=event.get('type')
                if kind=='delta':
                    if first is None: first=round(time.monotonic()-start,3)
                    pieces.append(event.get('text',''))
                elif kind=='done': done=event
                elif kind=='error': errors.append(str(event.get('error','unbekannt')))
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        errors.append(f'{type(exc).__name__}: {exc}')
    answer=((done or {}).get('answer') or ''.join(pieces)).strip()
    elapsed=round(time.monotonic()-start,3)
    if errors or done is None:
        status='BLOCKED'; reason='; '.join(errors) or 'Kein Abschlussereignis vom Backend'
    else:
        try: good,reason=evaluate(case_id,answer)
        except Exception as exc: good=False;reason=f'Prüfungsfehler: {exc}'
        status='PASS' if good else 'FAIL'
    return {'case':case_id,'question':question,'answer':answer,'status':status,'reason':reason,
            'seconds':elapsed,'first_token_seconds':first,'errors':errors}


def main(out=None):
    out=pathlib.Path(out or pathlib.Path.cwd()/'Ergebnisse')
    out.mkdir(parents=True,exist_ok=True)
    report={'time':datetime.datetime.now().astimezone().isoformat(),'status':'BLOCKED','cases':[],
            'note':'Prüft Modellantworten über den lokalen Backend-Endpunkt, nicht die Swift-App oder die Stimme.'}
    try:
        with request_json('/api/health') as r: health=json.load(r)
        with request_json('/api/native/session') as r: token=json.load(r).get('token')
        if not isinstance(token,str) or not token: raise RuntimeError('Kein Sitzungstoken')
        installed=health.get('installed',[])
        model=next((x for x in installed if x.startswith('qwen3:4b-instruct')),None) or next((x for x in installed if x.startswith('qwen3:4b')),None)
        if not model: raise RuntimeError('Qwen3 4B nicht installiert')
        report['model']=model
        for case in CASES:
            print('Prüfe:',case[0],flush=True)
            report['cases'].append(run_case(case,model,token))
        statuses=[c['status'] for c in report['cases']]
        report['status']=('BLOCKED' if 'BLOCKED' in statuses else
                          'FAIL' if 'FAIL' in statuses else 'PASS')
        report.update(summarize(report['cases']))
    except Exception as exc:
        report['error']=f'{type(exc).__name__}: {exc}'
    report.update(summarize(report['cases']))
    (out/'ATLAS_103_QUALITAET.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    lines=['# ATLAS 1.0.8 – Live-Gesprächsqualität','',f"Status: **{report['status']}**",f"Modell: {report.get('model','unbekannt')}",
           f"Ergebnis: {report['counts']}",f"Median Antwortdauer: {report.get('median_seconds')} s",f"Median erste Ausgabe: {report.get('median_first_token_seconds')} s",f"Bestehensquote (nur ausgeführte Tests): {report.get('pass_rate_percent')} %",f"Testabdeckung: {report.get('coverage_percent')} %",'']
    if 'error' in report: lines.append('Blockiert: '+report['error'])
    for case in report['cases']:
        lines.extend([f"## {case['status']} – {case['case']}",f"**Frage:** {case['question']}",
                      f"**Antwort:** {case['answer'] or '(leer)'}",f"**Prüfung:** {case['reason']}",
                      f"**Dauer:** {case['seconds']} s",''])
    lines.extend(['## Aussagekraft','Regelbasierte Prüfungen sind strenger als bloße Schlüsselworttests, aber keine vollständige semantische Bewertung.',
                  'Dieser Test verwendet einen definierten Test-Systemprompt und belegt nicht die Prompt-Konfiguration der Swift-App.',
                  'Die Benchmark-Fragen fordern keine Dateiaktionen an; eine Veränderung durch den Backend-Betrieb wird nicht garantiert.'])
    (out/'ATLAS_103_QUALITAET.md').write_text('\n'.join(lines),encoding='utf-8')
    print('Bericht:',out/'ATLAS_103_QUALITAET.md')
    return 0 if report['status']=='PASS' else 1

if __name__=='__main__': sys.exit(main(sys.argv[1] if len(sys.argv)>1 else None))
