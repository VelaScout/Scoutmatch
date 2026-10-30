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


# -- Erweiterter Formatwächter (1.0.1) ---------------------------------------------------------------------
# Deterministisch: Wenn die Frage ein knappes Format verlangt, wird die Antwort darauf zurechtgeschnitten –
# nur wenn sich das gesuchte Element eindeutig aus der Antwort ablesen lässt. Inhalt wird nie erfunden.

_YESNO = re.compile(r'\b(?:nur|antworte (?:nur |ausschließlich )?mit) (?:mit )?(?:ja oder nein|ja/nein|nein oder ja)\b|\b(?:only )?yes or no\b', re.I)
_TIME = re.compile(r'\bnur (?:die )?uhrzeit\b|\bformat hh:mm\b|\bim format hh:mm\b', re.I)
_SHORT = re.compile(r'\bnur (?:der|die|das|den)? ?(?:name|namen|nachname|nachnamen|vor- und nachname|vorname|wochentag|'
                    r'symbol|formel|jahreszahl|jahr|wort|ergebnis|stadt|land|planet|farbe|monat|datum|land|übersetzung)\b'
                    r'|\bnur (?:mit )?(?:dem|der) (?:namen|wochentag|ergebnis)\b|\boutput only the translation\b|\bgib nur (?:die|das) (?:übersetzung|ergebnis)\b', re.I)
_BULLETS = re.compile(r'\bgenau (zwei|drei|vier|fünf|\d+)\b[^.?!]{0,60}\b(?:aufzählung|spiegelstrich|stichpunkt|liste)', re.I)
_COUNTS = {'zwei': 2, 'drei': 3, 'vier': 4, 'fünf': 5}
_FORBIDDEN = re.compile(r'\bohne (?:das wort|den begriff) [„"\']?(\w+)[“"\']?', re.I)
_FUNCTION = re.compile(r'\b(?:funktion|function)\s+`?([A-Za-z_]\w*)\s*\(', re.I)


def requested_shape(user_text: str) -> str | None:
    """Wie requested_format, plus Ja/Nein, Uhrzeit, Kurzantwort und Aufzählung."""
    kind = requested_format(user_text)
    if kind:
        return kind
    t = user_text or ''
    if _YESNO.search(t):
        return 'yesno'
    if _TIME.search(t):
        return 'time'
    if _BULLETS.search(t):
        return 'bullets'
    if _SHORT.search(t):
        return 'short'
    return None


def _plain(answer: str) -> str:
    text = re.sub(r'(?s)<think>.*?</think>', '', answer or '')
    return text.replace('**', '').replace('`', '').strip()


def _last_line(answer: str) -> str:
    lines = [line.strip() for line in _plain(answer).splitlines() if line.strip()]
    return lines[-1] if lines else ''


def shape(kind: str | None, answer: str, question: str = '') -> str:
    """Antwort auf das verlangte Format bringen, sofern eindeutig möglich; sonst unverändert lassen."""
    if not kind or not answer:
        return answer
    text = _plain(answer)
    if kind == 'number':
        if conforms('number', text.rstrip('.')):
            return text.rstrip('.')
        numbers = re.findall(r'[+-]?\d+(?:[.,]\d+)*', _last_line(answer))
        numbers = numbers or re.findall(r'[+-]?\d+(?:[.,]\d+)*', text)
        return numbers[-1] if numbers else answer
    if kind == 'yesno':
        first = re.match(r'\W*(ja|nein|yes|no)\b', text, re.I)
        if first:
            word = first.group(1).lower()
            return 'Ja.' if word in ('ja', 'yes') else 'Nein.'
        said = {w.lower() for w in re.findall(r'\b(ja|nein)\b', text, re.I)}
        if len(said) == 1:
            return 'Ja.' if 'ja' in said else 'Nein.'
        return answer
    if kind == 'time':
        times = re.findall(r'\b(\d{1,2})[:.](\d{2})\b', _last_line(answer)) or re.findall(r'\b(\d{1,2})[:.](\d{2})\b', text)
        return f'{int(times[-1][0]):02d}:{times[-1][1]}' if times else answer
    if kind in ('short', 'word'):
        line = _last_line(answer)
        line = re.sub(r'^(?:antwort|ergebnis|lösung|answer)\s*:\s*', '', line, flags=re.I)
        if '=' in line:
            line = line.rsplit('=', 1)[1]
        bold = re.findall(r'\*\*([^*]{1,60})\*\*', answer or '')
        candidate = line.strip().strip('.').strip()
        if kind == 'word':
            words = re.findall(r'[^\W\d_]+', candidate)
            if len(words) == 1:
                return words[0]
            if bold and len(re.findall(r'[^\W\d_]+', bold[-1])) == 1:
                return bold[-1].strip()
            return answer
        if bold and len(bold[-1].split()) <= 4 and kind == 'short':
            return bold[-1].strip().strip('.')
        if 0 < len(candidate.split()) <= 6:
            # „Freitag Freitag“ → „Freitag“
            words = candidate.split()
            if len(words) > 1 and len(set(w.lower() for w in words)) == 1:
                candidate = words[0]
            return candidate
        if bold and len(bold[-1].split()) <= 6:
            return bold[-1].strip()
        return answer
    if kind == 'bullets':
        match = _BULLETS.search(question or '')
        count = None
        if match:
            raw = match.group(1).lower()
            count = _COUNTS.get(raw) or (int(raw) if raw.isdigit() else None)
        lines = [line.strip() for line in text.splitlines() if line.strip()]
        bullets = [re.sub(r'^([-*•–]|\d+[.)])\s+', '', line) for line in lines if re.match(r'^([-*•–]|\d+[.)])\s+', line)]
        if not bullets and len(lines) == 1:
            bullets = [part.strip() for part in re.split(r'\s*[;,/·|]\s*|\s+[-–]\s+|\bund\b', lines[0]) if part.strip()]
            if count and len(bullets) != count and re.fullmatch(r'[\wÄÖÜäöüß]+(?:-[\wÄÖÜäöüß]+)+', lines[0].strip()):
                bullets = lines[0].strip().split('-')         # „Apfel-Orange-Banane“
        if bullets and (count is None or len(bullets) == count):
            return '\n'.join(f'- {item.rstrip(".")}' for item in bullets)
        return answer
    return answer


def forbidden_word(question: str) -> str | None:
    match = _FORBIDDEN.search(question or '')
    return match.group(1).lower() if match else None


def avoid_word(answer: str, word: str) -> str:
    """Nur für „und“ gibt es einen sicheren Ersatz („sowie“); andere Wörter bleiben (Neuversuch durch den Aufrufer)."""
    if word == 'und':
        return re.sub(r'\bund\b', 'sowie', re.sub(r'\bUnd\b', 'Sowie', answer))
    return answer


def contains_word(answer: str, word: str) -> bool:
    return bool(re.search(r'\b' + re.escape(word) + r'\b', answer or '', re.I))


def fix_function_name(question: str, answer: str) -> str:
    """Verlangt die Frage eine Funktion `name(...)` und das Modell nennt sie anders (z. B. is_palindrom statt
    ist_palindrom), wird der Name angeglichen – nur bei genau einer definierten Funktion."""
    wanted = _FUNCTION.search(question or '')
    if not wanted:
        return answer
    name = wanted.group(1)
    defined = re.findall(r'^\s*def\s+([A-Za-z_]\w*)\s*\(', answer or '', re.M)
    if name in defined or len(set(defined)) != 1:
        return answer
    return re.sub(r'\b' + re.escape(defined[0]) + r'\b', name, answer)
