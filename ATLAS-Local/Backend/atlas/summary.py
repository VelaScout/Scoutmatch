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
        if 'qwen3:8b' not in models:
            hints.append('qwen3:8b fehlt (Aufgaben schwächer)')
        if real.get('chat_model'):
            reasoning = ' – DENK-MODELL (langsam)!' if real.get('chat_model_reasoning') else ''
            lines.append(f"Gespräch: {real['chat_model']}{reasoning} | Aufgaben: {real.get('agent_model', '?')}")
        if real.get('model_error'):
            hints.append(real['model_error'])
        results = real.get('results') or []
        passed = sum(1 for r in results if r.get('passed'))
        lines.append(f'Echte Aufgaben: {passed}/{len(results)} bestanden' if real.get('executed') else 'Echte Aufgaben: NICHT AUSGEFÜHRT (Ollama?)')
        cells = [f"{'OK' if r.get('passed') else 'XX'} {r['case'][:16]:<16} {str(r.get('total_s', '?')):>5}s" for r in results]
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
    lines.append('=============================================================')
    print('\n'.join(lines))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
