"""ATLAS offline-first comprehensive Mac audit. Never equates test passes with ChatGPT parity."""
from __future__ import annotations
import argparse, datetime, importlib.util, json, os, pathlib, platform, shutil, socket, subprocess, sys, time
from .equivalence_suite import CASES, DOMAINS, run as run_domains

CHECKS = [
 ('macos','macOS erkannt'),('apple_silicon','Apple Silicon erkannt'),
 ('python','Python >= 3.10'),('ollama_cli','Ollama installiert'),('ollama_api','Ollama erreichbar'),
 ('backend_api','ATLAS Backend erreichbar'),('voice_api','XTTS Sprachserver erreichbar'),
 ('swift','Swift-Compiler verfügbar'),('microphone','Mikrofon-Zugriff nachgewiesen'),
 ('speaker','Sprachausgabe tatsächlich geprüft'),('web_access','Internetrecherche nachgewiesen'),
 ('screen_access','Bildschirmzugriff nachgewiesen'),('video','Videoverstehen nachgewiesen'),
 ('mac_action','Mac-Aktion sicher ausgeführt'),('memory_persist','Langzeitgedächtnis über Neustart nachgewiesen')]

def tcp(port, host='127.0.0.1'):
    try:
        with socket.create_connection((host,port),timeout=1):return True
    except OSError:return False

def _run_unit_tests(out, add):
        test_cmd=[sys.executable,'-m','unittest','discover','-s',str(pathlib.Path(__file__).resolve().parents[1]/'tests'),'-p','test_*.py']
        start=time.monotonic()
        try:
            p=subprocess.run(test_cmd,capture_output=True,text=True,timeout=180,cwd=str(pathlib.Path(__file__).resolve().parents[1]),env={**os.environ,'PYTHONPATH':str(pathlib.Path(__file__).resolve().parents[1])})
            (out/'unit_tests.log').write_text((p.stdout+'\n'+p.stderr)[-250000:],encoding='utf-8')
            add('unit_tests','PASS' if p.returncode==0 else 'FAIL',f'Exitcode {p.returncode}, Dauer {time.monotonic()-start:.1f}s, siehe unit_tests.log')
        except subprocess.TimeoutExpired as e:
            add('unit_tests','BLOCKED','Testsuite nach 180 Sekunden beendet (Timeout); kein Bestehen behauptet')
            (out/'unit_tests.log').write_text(str(e),encoding='utf-8')
        except Exception as e:add('unit_tests','BLOCKED',repr(e))

def audit(out, skip_live=False, skip_unit=False):
    out=pathlib.Path(out).expanduser().resolve();out.mkdir(parents=True,exist_ok=True)
    results={};
    def add(key,status,detail):results[key]={'status':status,'detail':str(detail)}
    is_mac=sys.platform=='darwin'
    add('macos','PASS' if is_mac else 'BLOCKED',platform.platform())
    arm=platform.machine().lower() in ('arm64','aarch64')
    add('apple_silicon','PASS' if is_mac and arm else 'BLOCKED',platform.machine())
    add('python','PASS' if sys.version_info >= (3,10) else 'FAIL',sys.version.split()[0])
    add('ollama_cli','PASS' if shutil.which('ollama') else 'BLOCKED',shutil.which('ollama') or 'Nicht im PATH')
    add('ollama_api','PASS' if tcp(11434) else 'BLOCKED','127.0.0.1:11434')
    add('backend_api','PASS' if tcp(8765) else 'BLOCKED','127.0.0.1:8765 (Port nur als Indikator)')
    add('voice_api','PASS' if tcp(5002) else 'BLOCKED','127.0.0.1:5002; Portcheck ist kein Sprachqualitätstest')
    add('swift','PASS' if shutil.which('swift') else 'BLOCKED',shutil.which('swift') or 'Nicht gefunden')
    for key in ('microphone','speaker','web_access','screen_access','video','mac_action','memory_persist'):
        add(key,'REVIEW','Benötigt einen tatsächlichen Funktionstest mit überprüfbarem Nachweis; wird nicht fingiert')
    # Isolate child process so unexpected backend failures do not prevent report creation.
    if skip_unit:
        add('unit_tests','BLOCKED','Unit-Tests bewusst übersprungen')
    else:
        _run_unit_tests(out, add)
    # Unit tests completed; now run the live domain suite.
    # The helper prevents tests from blocking report creation.
    if skip_live:
        domains={'results':[{'id':c[0],'domain':c[1],'status':'BLOCKED' if c[3]=='exact' else 'REVIEW','reason':'Live-Test übersprungen' if c[3]=='exact' else 'Praxisnachweis nötig'} for c in CASES]}
    else:
        try:domains=run_domains(out/'zehn_bereiche')
        except Exception as e:
            add('domain_suite','BLOCKED',repr(e))
            domains={'results':[{'id':c[0],'domain':c[1],'status':'BLOCKED','reason':repr(e)} for c in CASES]}
    domain_rows=domains['results']; counts={s:sum(r['status']==s for r in domain_rows) for s in ('PASS','FAIL','BLOCKED','REVIEW')}
    report={'version':'1.0.11','date':datetime.datetime.now().astimezone().isoformat(),'platform':platform.platform(),
            'environment':results,'domain_counts':counts,'domain_results':domain_rows,
            'comparison':'Keine ChatGPT-Gleichwertigkeit nachgewiesen. ChatGPT/Claude benötigen identische externe Testläufe und unabhängige Bewertung.',
            'privacy':'Keine Daten an ChatGPT oder Claude gesendet; nur lokaler ATLAS-Endpunkt bei Live-Tests.'}
    (out/'gesamtbericht.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
    lines=['# ATLAS – vollständiger Mac-Testbericht','',f"Erstellt: {report['date']}",'',
           '**WICHTIG:** Alle grünen Häkchen beweisen keine Gleichwertigkeit mit ChatGPT. Für einen Vergleich müssen ChatGPT und Claude dieselben Aufgaben unabhängig bearbeiten.','',
           '## System und Integrationen','','| Test | Status | Erläuterung |','|---|---|---|']
    for k,v in results.items():lines.append(f"| {k} | {v['status']} | {v['detail'].replace('|','/')} |")
    lines+=['','## Zehn Leistungsbereiche','','| Bereich | Bestanden | Fehlgeschlagen | Blockiert | Praxisprüfung |','|---|---:|---:|---:|---:|']
    for key,name in DOMAINS.items():
        sub=[r for r in domain_rows if r['domain']==key]; c={s:sum(r['status']==s for r in sub) for s in counts}
        lines.append(f"| {name} | {c['PASS']} | {c['FAIL']} | {c['BLOCKED']} | {c['REVIEW']} |")
    lines+=['','## Gesamtstand',f"Automatisch bestanden: **{counts['PASS']}/40**; Fehlgeschlagen: **{counts['FAIL']}**; blockiert: **{counts['BLOCKED']}**; manuelle Praxisnachweise: **{counts['REVIEW']}**.",
            '', '## Nächste Schritte','1. Blockierte Tests nach Start von Ollama und ATLAS erneut ausführen.',
            '2. Praxisaufgaben mit tatsächlichen Audio-, Datei-, Bildschirm- und Werkzeugnachweisen prüfen.',
            '3. Identischen Testkatalog mit ChatGPT und Claude ausführen und die Ergebnisse blind bewerten.',
            '4. Erst danach eine begrenzte, auf diese Aufgaben bezogene Gleichwertigkeitsaussage treffen.']
    (out/'GESAMTBERICHT.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    return report

def main(argv=None):
    p=argparse.ArgumentParser();p.add_argument('--out',default='ATLAS-GESAMTTEST-ERGEBNISSE');p.add_argument('--skip-live',action='store_true');p.add_argument('--skip-unit',action='store_true')
    a=p.parse_args(argv);report=audit(a.out,a.skip_live,a.skip_unit)
    print('Bericht:',pathlib.Path(a.out).resolve()/'GESAMTBERICHT.md')
    print('Ergebnisse:',report['domain_counts'])
    return 0
if __name__=='__main__':sys.exit(main())
