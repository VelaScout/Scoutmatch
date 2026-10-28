"""Objective aggregation for ATLAS live tests; blocked tests never count as successes."""
from __future__ import annotations
import statistics


def summarize(cases: list[dict]) -> dict:
    counts = {status: sum(c.get('status') == status for c in cases)
              for status in ('PASS', 'FAIL', 'BLOCKED')}
    completed = counts['PASS'] + counts['FAIL']
    timings = [c['seconds'] for c in cases if c.get('status') in ('PASS', 'FAIL')
               and isinstance(c.get('seconds'), (float, int)) and c['seconds'] >= 0]
    first = [c['first_token_seconds'] for c in cases if c.get('status') in ('PASS', 'FAIL')
             and isinstance(c.get('first_token_seconds'), (float, int)) and c['first_token_seconds'] >= 0]
    return {'counts': counts, 'total': len(cases), 'evaluated': completed,
            'pass_rate_percent': round(100 * counts['PASS'] / completed, 1) if completed else None,
            'coverage_percent': round(100 * completed / len(cases), 1) if cases else None,
            'median_seconds': round(statistics.median(timings), 2) if timings else None,
            'median_first_token_seconds': round(statistics.median(first), 2) if first else None,
            'ready_for_comparison': len(cases) >= 10 and counts['BLOCKED'] == 0}
