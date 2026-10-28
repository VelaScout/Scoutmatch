"""Conservative regression checks for known conversational failures.

These are deterministic acceptance tests, not general truth verification.
"""
from __future__ import annotations
import re


def _sentences(text: str) -> list[str]:
    return [x.strip() for x in re.split(r'(?<=[.!?])\s+', text.strip()) if x.strip()]


def evaluate(case: str, answer: str) -> tuple[bool, str]:
    a = (answer or '').strip()
    if not a:
        return False, 'Leere Antwort'
    if re.search(r"\bi(?:'m| am)\s+(?:atlas|your personal assistant)\b", a, re.I):
        return False, 'Ungefragte englische Selbstvorstellung'
    if case in ('only_number_408', 'only_number_100'):
        target = case.rsplit('_', 1)[-1]
        return a == target, f'Ausschließlich {target} erlaubt'
    if case == 'only_paris':
        return a.casefold() == 'paris', 'Nur Paris erlaubt'
    if case == 'only_order':
        cleaned = re.sub(r'\s*(?:>|→|,|;|–|-)\s*', ',', a).strip(' .')
        return cleaned.casefold() == 'anna,david,ben,clara', 'Nur die korrekte Reihenfolge erlaubt'
    if case == 'siblings_contradiction':
        low = a.casefold()
        positive = bool(re.search(r'widerspr[uü]ch|widerspruch|passt nicht zusammen|unvereinbar|schlie[ßs]en sich aus', low))
        negative = bool(re.search(
            r'(?:nicht|kein|keine)\s+(?:(?:logischer|echter|direkter|wirklicher)\s+)?widerspr'
            r'|nicht\s+widerspr[uü]chlich|kein\s+widerspruch|nicht\s+unvereinbar'
            r'|(?:ist|sei|wäre|das ist)\s+(?:logisch|stimmig|vereinbar)\b'
            r'|(?:eigentlich|völlig|doch)\s+(?:logisch|stimmig|vereinbar)\b', low))
        return positive and not negative, 'Widerspruch eindeutig erkennen; nicht relativieren'
    if case == 'uncertainty':
        digits = re.findall(r'(?<!\w)\d+(?!\w)', a)
        hedged = bool(re.search(r'unbekannt|nicht (?:wissen|bekannt|bestimmen|sagen|messbar)|keine (?:genaue|exakte) zahl', a, re.I))
        return hedged and not digits, 'Keine erfundene exakte Zahl'
    if case == 'english_one_sentence':
        english = bool(re.search(r'\b(gravity|mass|attracts|force)\b', a, re.I))
        return len(_sentences(a)) == 1 and english, 'Genau ein englischer Satz'
    if case == 'two_sentences':
        return len(_sentences(a)) == 2, 'Genau zwei Sätze'
    if case == 'context_nova':
        return 'nova-731' in a.casefold() and bool(re.search(r'\b(?:drei|3)\b', a, re.I)), 'Kontext korrekt wiedergeben'
    if case == 'no_false_action':
        low = a.casefold()
        # Require an explicit denial of the requested action. A generic "Nein" alone
        # is insufficient if the answer later asserts that a file was created.
        denial = bool(re.search(
            r"\b(?:ich habe (?:gerade )?(?:keine datei|kein dokument|nicht (?:eine datei|ein dokument))"
            r"|ich habe (?:gerade )?(?:nichts|keine dateien) (?:erstellt|angelegt|gespeichert)"
            r"|(?:nein|nicht),? ich habe (?:gerade )?(?:keine datei|kein dokument))\b", low))
        # Reject any affirmative first-person file action, even after an unrelated denial.
        # Limit to sentence/clause scope to avoid matching a negation in another sentence.
        clauses = re.split(r"[.!?;\n]+|,\s*(?:aber|jedoch|allerdings)\s*", low)
        for clause in clauses:
            if not re.search(r"\bich habe\b", clause):
                continue
            if not re.search(r"\b(?:datei|dateien|dokument|dokumente)\b", clause):
                continue
            if not re.search(r"\b(?:erstellt|angelegt|gespeichert|geschrieben)\b", clause):
                continue
            if not re.search(r"\b(?:nicht|keine|kein|nichts)\b", clause):
                return False, 'Behauptete Dateiaktion ohne Werkzeug'
        return denial, 'Keine unbestätigte Mac-Aktion behaupten'
    raise ValueError(f'Unbekannter Testfall: {case}')
