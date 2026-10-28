"""Ein-Klick-Diagnose für lokale Intelligenz. Keine Gleichwertigkeitsbehauptung."""
from __future__ import annotations
import argparse
import datetime
import json
import os
from pathlib import Path
from .intelligence_benchmark import ollama_models, assess
from .intelligence_ab import paired_trial, summarize
from .intelligence_benchmark import QUESTIONS

PREFERRED = ('qwen3:14b', 'qwen3:8b', 'qwen3:4b-instruct-2507-q4_K_M', 'qwen3:4b-instruct', 'qwen3:4b')

def choose_models(installed, limit=2):
    """Keine Downloads, keine Cloud-Modelle und höchstens zwei Modellvarianten."""
    local = [m for m in installed if 'cloud' not in m.lower()]
    def key(m):
        return next((i for i, p in enumerate(PREFERRED) if m == p or m.startswith(p + ':')), len(PREFERRED))
    return sorted(local, key=key)[:limit]

def report_markdown(data):
    lines = ['# ATLAS – Intelligenztest auf diesem Mac', '',
             'Zeitpunkt: ' + data['timestamp'], '',
             '**Wichtig:** Dieser Test misst lokale Kurzantwort-Qualität. Er ist kein ChatGPT- oder Claude-Benchmark. '
             'Ein Zielwert von 50/100 ist ohne gemeinsamen, validierten Vergleich nicht belegbar.', '',
             '## Modellvergleich', '', '| Modell | Richtig | Erfolgreich ausgeführt |', '|---|---:|---:|']
    for r in data['benchmarks']:
        lines.append(f"| {r['model']} | {r['passed']}/{r['total']} | {r['attempted']}/{r['total']} |")
    if data['ab']:
        a = data['ab']['summary']
        lines += ['', '## Denkmodus A/B', '',
                  f"Modell: {data['ab']['model']}",
                  f"Direkt: {a['direct_correct']}/{a['total']}; mit Selbstprüfung: {a['reviewed_correct']}/{a['total']}; "
                  f"Verbesserungen: {a['improved']}; Verschlechterungen: {a['regressed']}.",
                  'Selbstprüfung ist nur besser, wenn sie im Test tatsächlich mehr korrekte Antworten liefert.']
    lines += ['', '## Interpretation', '',
              'Keine 50/100-Freigabe. Keine echte Vergleichsmessung mit ChatGPT und Claude.',
              'Bitte die JSON-Datei für die genaue Analyse in ChatGPT hochladen.', '']
    return '\n'.join(lines)

def run(url='http://127.0.0.1:11434', output=None, timeout=90, ab_count=8):
    installed = ollama_models(url)
    models = choose_models(installed)
    if not models:
        raise RuntimeError('Kein lokales Ollama-Modell gefunden. Ollama starten und ein lokales Modell installieren.')
    benchmarks = [assess(m, url, timeout) for m in models]
    completed = [r for r in benchmarks if r['attempted'] == r['total']]
    best = max(completed, key=lambda r: r['passed']) if completed else None
    ab = None
    if best:
        trials = []
        for category, question, expected in QUESTIONS[:ab_count]:
            item = paired_trial(best['model'], question, expected, url, timeout)
            item['category'] = category
            trials.append(item)
        ab = {'model': best['model'], 'summary': summarize(trials), 'results': trials}
    result = {'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'installed_models': installed, 'tested_models': models, 'benchmarks': benchmarks,
              'ab': ab, 'best_completed_model': best['model'] if best else None,
              'goal_50_verified': False,
              'limitations': 'No ChatGPT/Claude same-task test; scores are not 0–100 general intelligence ratings.'}
    dest = Path(output or Path.home() / 'Downloads' / 'ATLAS-Testberichte')
    dest.mkdir(parents=True, exist_ok=True)
    (dest / 'ATLAS-Intelligenz-Ergebnis.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    (dest / 'ATLAS-Intelligenz-Bericht.md').write_text(report_markdown(result), encoding='utf-8')
    return result

def main(argv=None):
    p = argparse.ArgumentParser()
    p.add_argument('--output')
    p.add_argument('--url', default='http://127.0.0.1:11434')
    p.add_argument('--timeout', type=int, default=90)
    p.add_argument('--ab-count', type=int, default=8)
    args = p.parse_args(argv)
    if not 1 <= args.ab_count <= len(QUESTIONS):
        p.error('ab-count außerhalb des erlaubten Bereichs')
    try:
        data = run(args.url, args.output, args.timeout, args.ab_count)
    except Exception as exc:
        print('ATLAS-Test konnte nicht abgeschlossen werden:', exc)
        return 2
    for r in data['benchmarks']:
        print(f"{r['model']}: {r['passed']}/{r['total']} korrekt ({r['attempted']} ausgeführt)")
    if data['ab']:
        a = data['ab']['summary']
        print(f"Denkmodus A/B: {a['direct_correct']} direkt / {a['reviewed_correct']} geprüft")
    print('Berichte unter: ' + str(Path(args.output or Path.home() / 'Downloads' / 'ATLAS-Testberichte')))
    print('50/100 noch nicht verifiziert: Es fehlen direkte Vergleichstests mit ChatGPT und Claude.')
    return 0 if data['best_completed_model'] and (not data['ab'] or data['ab']['summary']['complete']) else 2

if __name__ == '__main__':
    raise SystemExit(main())
