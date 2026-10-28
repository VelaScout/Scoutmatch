"""Conservative, deterministic output-format checks for deliberative replies.

No semantic correctness claims; only explicit formatting requests are enforced.
"""
from __future__ import annotations
import re


def requested_format(user_text: str) -> str | None:
    t = (user_text or '').casefold()
    if re.search(r'\b(?:nur (?:die )?zahl|antworte (?:nur |ausschließlich )?mit (?:der |einer )?zahl|only (?:the )?number)\b', t):
        return 'number'
    if re.search(r'\b(?:nur (?:die )?reihenfolge|only (?:the )?order)\b', t):
        return 'order'
    if re.search(r'\b(?:genau ein(?:em|en)? wort|nur ein wort|one word only|exactly one word)\b', t):
        return 'word'
    return None


def conforms(kind: str | None, answer: str) -> bool:
    a = (answer or '').strip()
    if not a:
        return False
    if kind == 'number':
        return bool(re.fullmatch(r'[+-]?(?:\d+(?:[.,]\d+)?|[.,]\d+)', a))
    if kind == 'order':
        # Comma, arrow or greater-than separated short names, no explanation.
        return bool(re.fullmatch(r'[\wÄÖÜäöüß-]+(?:\s*(?:,|>|→|–)\s*[\wÄÖÜäöüß-]+){1,15}\.?', a))
    if kind == 'word':
        return bool(re.fullmatch(r'[^\W\d_]+', a, re.UNICODE))
    return True
