"""Kompakte Zusammenfassung der Mac-Tests – passt auf einen Terminal-Bildschirm (für einen Screenshot).

Aufruf: python3 -m atlas.summary <build-Ordner>
"""
import json
import sys
from pathlib import Path


def load(path: Path):
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return None


def main() -> int:
    build = Path(sys.argv[1] if len(sys.argv) > 1 else 'build')
    real = load(build / 'MAC-ECHTE-MODELLTESTS.json')
    diag = load(build / 'MAC-DIAGNOSE.json')
    lines = ['', '=========== ATLAS TESTERGEBNIS (bitte Screenshot) ===========']
    if real:
        models = real.get('installed_models') or []
        lines.append('Modelle: ' + (', '.join(models) or 'KEINE'))
        hints = []
        if not any(m.startswith('qwen3:4b-instruct') for m in models):
            hints.append('schnelles Modell qwen3:4b-instruct fehlt → AKTUALISIEREN erneut')
        if real.get('chat_model'):
            reasoning = ' – DENK-MODELL (langsam)!' if real.get('chat_model_reasoning') else ''
            lines.append(f"Gespräch: {real['chat_model']}{reasoning} | Aufgaben: {real.get('agent_model', '?')}")
        if real.get('model_error'):
            hints.append(real['model_error'])
        for model, c in (real.get('comparison') or {}).items():
            mark = '  ← gewählt' if model == real.get('best_model') else ''
            lines.append(f"  {model[:30]:<30} {c['passed']}/{c['total']}  Ø {c['avg_s']}s{mark}")
        results = real.get('results') or []
        status = [r.get('status') or ('BESTANDEN' if r.get('passed') else 'FEHLGESCHLAGEN') for r in results]
        counts = {k: status.count(k) for k in ('BESTANDEN', 'FEHLGESCHLAGEN', 'NICHT AUSGEFÜHRT')}
        if real.get('executed'):
            lines.append(f"Echte Aufgaben: {counts['BESTANDEN']} BESTANDEN, {counts['FEHLGESCHLAGEN']} FEHLGESCHLAGEN, "
                         f"{counts['NICHT AUSGEFÜHRT']} NICHT AUSGEFÜHRT")
            reached = counts['BESTANDEN'] == len(results) and results
            lines.append(f"Ziel Claude-Niveau: alle {len(results)} bestanden – {'erreicht' if reached else 'noch nicht erreicht'}")
            feedback = sorted(r['first_feedback_s'] for r in results if r.get('first_feedback_s') is not None)
            totals = sorted(r['total_s'] for r in results if r.get('total_s') is not None)
            if feedback and totals:
                lines.append(f"Zeiten (Median): erste Rückmeldung {feedback[len(feedback) // 2]} s, "
                             f"vollständiges Ergebnis {totals[len(totals) // 2]} s")
        else:
            lines.append('Echte Aufgaben: NICHT AUSGEFÜHRT (Ollama läuft nicht oder kein Modell)')
        mark = {'BESTANDEN': 'OK', 'FEHLGESCHLAGEN': 'XX', 'NICHT AUSGEFÜHRT': '--'}
        cells = [f"{mark[st]} {r['case'][:16]:<16} {str(r.get('total_s', '?')):>5}s" for r, st in zip(results, status)]
        for i in range(0, len(cells), 2):
            lines.append('  ' + '   '.join(cells[i:i + 2]))
        if hints:
            lines.append('Hinweis: ' + '; '.join(hints))
    else:
        lines.append('Echte Modelltests: keine Ergebnisdatei gefunden.')
    if diag and diag.get('benchmark'):
        cells = []
        for item in diag['benchmark']:
            check = {True: 'OK', False: 'XX', None: '--'}[item.get('automatic_check')]
            total = (item.get('metrics') or {}).get('total_s', '?')
            cells.append(f"{check} {item['case'][:11]:<11} {str(total):>5}s")
        lines.append('Diagnose (' + str(diag['benchmark'][0].get('actual_model') or diag['benchmark'][0]['model']) + '):')
        for i in range(0, len(cells), 3):
            lines.append('  ' + '  '.join(cells[i:i + 3]))
    if diag and diag.get('audio'):
        audio = diag['audio']
        lines.append('Spracherkennung: ' + ('OK' if audio.get('nonempty') else 'FEHLER ' + str(audio.get('error', ''))[:50]))
    sandbox = load(build / 'MAC-SANDBOX.json')
    if sandbox:
        if not sandbox.get('available'):
            lines.append('Sandbox: sandbox-exec NICHT vorhanden')
        else:
            lines.append(f"Sandbox: Fähigkeiten {sandbox.get('none', '?')[:40]} | Werkstatt {sandbox.get('localhost', '?')[:40]}")
    restart = load(build / 'MAC-NEUSTART.json')
    if restart:
        lines.append(f"Neustart-Datenerhalt: {restart.get('status')}" + (f" (verloren: {restart['lost']})" if restart.get('lost') else ''))
    lines.append('OK = BESTANDEN · XX = FEHLGESCHLAGEN · -- = NICHT AUSGEFÜHRT')
    lines.append('=============================================================')
    print('\n'.join(lines))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
