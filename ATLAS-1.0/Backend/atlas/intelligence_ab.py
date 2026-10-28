"""Paired A/B test of direct vs. two-pass reasoning on identical Ollama questions.

Scores deterministic short answers; does not imply general intelligence parity.
"""
from __future__ import annotations
import argparse
import json
import time
import urllib.request
from pathlib import Path
from .intelligence_benchmark import QUESTIONS, normalize
from .intelligence_challenges import CHALLENGES


def query(model, messages, url, timeout):
    payload = json.dumps({'model': model, 'stream': False, 'messages': messages,
                          'options': {'temperature': 0}}).encode('utf-8')
    req = urllib.request.Request(url.rstrip('/') + '/api/chat', data=payload,
                                 headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        data = json.load(response)
    answer = data.get('message', {}).get('content', '').strip()
    if not answer:
        raise ValueError('Leere Modellantwort')
    return answer


def paired_trial(model, question, expected, url, timeout, query_fn=query):
    messages = [{'role': 'system', 'content': 'Answer precisely and follow the requested output format.'},
                {'role': 'user', 'content': question}]
    result = {'question': question, 'expected': expected, 'model': model}
    for mode in ('direct', 'reviewed'):
        start = time.monotonic()
        try:
            if mode == 'direct':
                answer = query_fn(model, messages, url, timeout)
            else:
                draft = query_fn(model, messages, url, timeout)
                answer = query_fn(model, messages + [
                    {'role': 'assistant', 'content': draft},
                    {'role': 'user', 'content': 'Check your previous answer for mistakes and correct it. '
                     'Keep the original required output format. Output only the final answer.'}
                ], url, timeout)
            result[mode] = {'answer': answer, 'correct': normalize(answer) == normalize(expected),
                            'error': None, 'seconds': round(time.monotonic() - start, 3)}
        except Exception as exc:
            result[mode] = {'answer': '', 'correct': False, 'error': str(exc),
                            'seconds': round(time.monotonic() - start, 3)}
    return result


def summarize(results):
    total = len(results)
    complete = all(not r[m]['error'] for r in results for m in ('direct', 'reviewed')) and total > 0
    direct = sum(r['direct']['correct'] for r in results)
    reviewed = sum(r['reviewed']['correct'] for r in results)
    improved = sum(not r['direct']['correct'] and r['reviewed']['correct'] for r in results)
    regressed = sum(r['direct']['correct'] and not r['reviewed']['correct'] for r in results)
    return {'total': total, 'complete': complete, 'direct_correct': direct,
            'reviewed_correct': reviewed, 'improved': improved, 'regressed': regressed,
            'net_gain': reviewed-direct,
            'review_is_better': bool(complete and reviewed > direct and improved > regressed),
            'direct_seconds': round(sum(r['direct']['seconds'] for r in results), 2),
            'reviewed_seconds': round(sum(r['reviewed']['seconds'] for r in results), 2)}


def main(argv=None):
    parser = argparse.ArgumentParser(description='Real paired Ollama test: direct vs. review')
    parser.add_argument('--model', default='qwen3:8b')
    parser.add_argument('--url', default='http://127.0.0.1:11434')
    parser.add_argument('--timeout', type=int, default=120)
    parser.add_argument('--output', default='intelligenz-ab.json')
    args = parser.parse_args(argv)
    results = []
    for category, question, expected in QUESTIONS + CHALLENGES:
        item = paired_trial(args.model, question, expected, args.url, args.timeout)
        item['category'] = category
        results.append(item)
    summary = summarize(results)
    report = {'model': args.model, 'summary': summary, 'results': results,
              'limitations': 'Short exact-answer tasks only. No real ChatGPT/Claude comparison. '
                             'No evidence of general intelligence equivalence.'}
    path = Path(args.output)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding='utf-8')
    print(f"Direct {summary['direct_correct']}/{summary['total']}, "
          f"Review {summary['reviewed_correct']}/{summary['total']}, "
          f"regressions {summary['regressed']}, complete={summary['complete']}")
    print(f'Bericht: {path}')
    return 0 if summary['complete'] else 2

if __name__ == '__main__':
    raise SystemExit(main())
