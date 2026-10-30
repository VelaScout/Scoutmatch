"""Reproducible *small* local Ollama model benchmark. Never a ChatGPT equivalence claim."""
import argparse
import json
import re
import time
import urllib.request
from urllib.parse import urlsplit
from pathlib import Path
from .intelligence_challenges import CHALLENGES

# Short exact-answer tasks avoid unreliable LLM-as-judge scoring.
QUESTIONS = [
    ('math', '37 * 24. Reply with only the number.', '888'),
    ('algebra', 'Solve 3x + 7 = 31. Reply with only the value of x.', '8'),
    ('fractions', 'What is 3/4 + 1/8? Reply with only a simplified fraction.', '7/8'),
    ('logic', 'All roses are flowers. Some flowers are red. Must some roses be red? Reply yes or no.', 'no'),
    ('logic', 'If A > B and B > C, must A > C? Reply yes or no.', 'yes'),
    ('rates', '150 km in 2.5 hours: average speed in km/h? Reply with only the number.', '60'),
    ('percent', '80 euros increased by 25 percent: new price? Reply with only the number.', '100'),
    ('counting', 'How many outcomes are possible when tossing three coins? Reply with only the number.', '8'),
    ('probability', 'Probability of heads with a fair coin, in percent? Reply with only the number.', '50'),
    ('sequence', 'Continue 2, 6, 12, 20, 30, ... Reply with only the next number.', '42'),
    ('reasoning', 'Can correlation alone prove causation? Reply yes or no.', 'no'),
    ('units', 'How many milliliters are in 2.5 liters? Reply with only the number.', '2500'),
    ('logic', 'Three boxes are labeled Apples, Oranges, Mixed. All labels are wrong. Which labeled box must you sample to determine all contents? Reply with only the label.', 'mixed'),
    ('math', 'A 120 euro item is discounted 20% then taxed 10%. Final price in euros? Number only.', '105.6'),
    ('logic', 'A statement says "All birds can fly". Does a penguin refute it? Reply yes or no.', 'yes'),
    ('probability', 'Two fair dice: how many ordered outcomes sum to 7? Number only.', '6'),
    ('algebra', 'If x+y=10 and x-y=4, what is x? Number only.', '7'),
    ('units', 'Convert 72 km/h to m/s. Number only.', '20'),
]

def normalize(answer):
    answer = re.sub(r'<think>.*?</think>', '', str(answer), flags=re.S|re.I).strip()
    answer = answer.strip(' `\n\t.').lower().replace(',', '.')
    answer = re.sub(r'\s+', '', answer)
    return answer

def safe_local_url(url):
    """Benchmarks are local-only: never send questions to a remote endpoint."""
    parsed = urlsplit(url)
    if parsed.scheme != 'http' or parsed.hostname not in ('127.0.0.1', 'localhost', '::1') or parsed.username or parsed.password or parsed.query or parsed.fragment or parsed.path not in ('', '/'):
        raise ValueError('Nur lokale Ollama-Adressen sind erlaubt (http://127.0.0.1:11434).')
    return url.rstrip('/')


def ollama_models(url, timeout=10):
    with urllib.request.urlopen(safe_local_url(url) + '/api/tags', timeout=timeout) as response:
        return [m['name'] for m in json.load(response).get('models', []) if m.get('name')]

def assess(model, url='http://127.0.0.1:11434', timeout=90):
    results = []
    for category, question, expected in QUESTIONS + CHALLENGES:
        payload = json.dumps({'model': model, 'stream': False, 'messages': [
            {'role': 'system', 'content': 'Answer exactly in the requested format. No explanations.'},
            {'role': 'user', 'content': question}], 'options': {'temperature': 0}}).encode()
        started = time.monotonic()
        try:
            request = urllib.request.Request(safe_local_url(url)+'/api/chat', data=payload,
                                             headers={'Content-Type': 'application/json'})
            with urllib.request.urlopen(request, timeout=timeout) as response:
                data = json.load(response)
            answer = data.get('message', {}).get('content', '').strip()
            error = None
        except Exception as exc:
            answer, error = '', str(exc)
        results.append({'category': category, 'question': question, 'expected': expected,
                        'answer': answer, 'passed': error is None and normalize(answer) == normalize(expected),
                        'error': error, 'seconds': round(time.monotonic()-started, 2)})
    attempted = sum(r['error'] is None for r in results)
    categories = sorted({r['category'] for r in results})
    domain_scores = {c: {'correct': sum(r['passed'] for r in results if r['category'] == c),
                         'total': sum(r['category'] == c for r in results)} for c in categories}
    return {'model': model, 'domain_scores': domain_scores, 'passed': sum(r['passed'] for r in results), 'attempted': attempted,
            'total': len(results), 'results': results,
            'warning': '28 deterministic short-answer questions; NOT evidence of ChatGPT-level intelligence.'}

def summarize_trials(trials):
    """Prefer consistent accuracy over a lucky single run; reject incomplete runs."""
    if not trials:
        return {'eligible': False, 'accuracy': 0.0, 'worst_passed': 0, 'consistency': 0.0}
    complete = all(t['attempted'] == t['total'] and t['total'] > 0 for t in trials)
    total = sum(t['total'] for t in trials)
    accuracy = sum(t['passed'] for t in trials) / total if total else 0.0
    worst = min(t['passed'] for t in trials)
    # Fraction of questions answered correctly in *every* trial.
    lengths = {len(t['results']) for t in trials}
    consistency = (sum(all(t['results'][i]['passed'] for t in trials)
                       for i in range(next(iter(lengths)))) / next(iter(lengths))
                   if len(lengths) == 1 and next(iter(lengths)) else 0.0)
    return {'eligible': complete, 'accuracy': round(accuracy, 4),
            'worst_passed': worst, 'consistency': round(consistency, 4)}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--model', action='append', help='Repeat to compare models; default: all installed Ollama models')
    parser.add_argument('--url', default='http://127.0.0.1:11434')
    parser.add_argument('--output', default='intelligenz-benchmark.json')
    parser.add_argument('--timeout', type=int, default=90)
    parser.add_argument('--runs', type=int, default=2, help='Repeat each model test to check reliability')
    args = parser.parse_args()
    if not 1 <= args.runs <= 10:
        parser.error('--runs muss zwischen 1 und 10 liegen')
    try:
        models = args.model or ollama_models(args.url)
    except Exception as exc:
        print(f'Ollama nicht erreichbar: {exc}')
        return 2
    if not models:
        print('Keine lokalen Ollama-Modelle gefunden. Zuerst ein Modell installieren.')
        return 2
    reports = []
    for model in models:
        trials = [assess(model, args.url, args.timeout) for _ in range(args.runs)]
        summary = summarize_trials(trials)
        reports.append({'model': model, 'trials': trials, **summary})
    # Do not silently prefer a model when some or all calls failed.
    complete = [r for r in reports if r['eligible']]
    ranked = sorted(complete, key=lambda r: (-r['consistency'], -r['accuracy'],
                    sum(x['seconds'] for trial in r['trials'] for x in trial['results'])))
    report = {'results': reports, 'best_completed_model': ranked[0]['model'] if ranked else None,
              'limitations': 'Small fixed-question test; possible memorization; no validated ChatGPT comparison.'}
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    Path(args.output).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    for r in reports:
        print(f"{r['model']}: accuracy {r['accuracy']:.1%}, consistent {r['consistency']:.1%}, eligible={r['eligible']}")
    print(f'Bericht: {args.output}')
    return 0 if ranked else 2

if __name__ == '__main__':
    raise SystemExit(main())
