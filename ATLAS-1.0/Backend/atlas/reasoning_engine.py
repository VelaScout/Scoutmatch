"""Local multi-candidate answer verification for complex questions.

No hidden chain of thought requested; never treats self-judgment as external evidence.
"""
from __future__ import annotations

import re
from dataclasses import dataclass

from .llm import strip_think
from .answer_guard import requested_format, conforms, requested_shape, shape


@dataclass(frozen=True)
class ReasoningResult:
    answer: str
    drafts: tuple[str, str]
    disagreement: bool
    calls: int


def solve(llm, model: str, messages: list[dict], *, stop=None) -> ReasoningResult:
    """Two independent answers and one critique. Costs 3 model calls.

    A third model call is NOT independent verification; the final instruction
    explicitly requests uncertainty when candidates cannot be reconciled.
    """
    def cancelled():
        return stop is not None and stop.is_set()

    if cancelled():
        return ReasoningResult('', ('', ''), False, 0)

    prompts = (
        'Beantworte die Frage eigenständig, präzise und überprüfbar. '
        'Nenne relevante Annahmen. Erfinde keine Fakten oder Quellen. '
        'Gib nur die Antwort, keine privaten Denkprotokolle.',
        'Löse dieselbe Frage UNABHÄNGIG von einem vorherigen Versuch. '
        'Prüfe alternative Interpretationen, Randfälle und Rechenfehler. '
        'Erfinde keine Fakten oder Quellen. Gib nur die Antwort, keine privaten Denkprotokolle.',
    )
    drafts = []
    for prompt in prompts:
        if cancelled():
            return ReasoningResult('', tuple((drafts + [''] * (2-len(drafts)))[:2]), False, len(drafts))
        result = llm.chat(model, messages + [{'role': 'system', 'content': prompt}],
                          num_predict=1000, timeout=180, temperature=0.35)
        draft = result.content.strip()
        if not draft:
            raise ValueError('Leerer unabhängiger Lösungsversuch')
        drafts.append(draft)

    if cancelled():
        return ReasoningResult('', (drafts[0], drafts[1]), drafts[0] != drafts[1], 2)

    review = ('Vergleiche zwei UNABHÄNGIGE Antwortkandidaten auf dieselbe Nutzerfrage. '
              'Prüfe Widersprüche, Einheiten, logische Fehler, unbelegte Aussagen und Annahmen. '
              'Übernimm nicht automatisch eine Behauptung, nur weil sie in beiden Kandidaten steht. '
              'Wenn du einen Konflikt nicht anhand nachvollziehbarer Belege lösen kannst, '
              'sage offen, was unklar bleibt. Erfinde keine Quellen. '
              'Beachte die ursprüngliche Formatvorgabe des Nutzers strikt: Nur Zahl bedeutet ausschließlich eine Zahl; '
              'Nur Reihenfolge bedeutet ausschließlich die Reihenfolge. Keine Einleitung, keine Wiederholung der Frage. '
              'Vermeide unnötige Erklärungen und widersprüchliche Zusätze. '
              'Antworte nur mit der besten sachlichen Endantwort.\n\n'
              'Kandidat A:\n' + drafts[0] + '\n\nKandidat B:\n' + drafts[1])
    final = llm.chat(model, messages + [{'role': 'user', 'content': review}],
                     num_predict=1300, timeout=180, temperature=0.1).content.strip()
    if not final:
        raise ValueError('Leere Schlussprüfung')
    # One bounded correction attempt for explicit formatting instructions.
    # This does not certify the factual accuracy of the final answer.
    original_question = next((m.get('content', '') for m in reversed(messages)
                              if m.get('role') == 'user'), '')
    kind = requested_format(original_question)
    calls = 3
    if kind and not conforms(kind, final) and not cancelled():
        correction = ('Deine vorherige Antwort hat die ausdrückliche Formatvorgabe verletzt. '
                      'Gib die sachlich korrekte Antwort erneut aus, ohne Erklärung, '
                      'ohne Einleitung und ausschließlich im verlangten Format. '
                      'Erfinde keine Information.')
        corrected = llm.chat(model, messages + [
            {'role': 'assistant', 'content': final},
            {'role': 'user', 'content': correction}],
            num_predict=120, timeout=60, temperature=0.1).content.strip()
        calls += 1
        if conforms(kind, corrected):
            final = corrected
        # Never pretend the formatting was repaired when it was not.
    return ReasoningResult(final, (drafts[0], drafts[1]), drafts[0] != drafts[1], calls)


VOTE_PROMPT = ('Löse die Aufgabe sorgfältig und Schritt für Schritt im Kopf. Prüfe dein Ergebnis mit einer Gegenprobe '
               '(z. B. durch Einsetzen). Achte auf typische Denkfallen. Gib danach NUR die Endantwort aus, genau im '
               'verlangten Format und in der Sprache der Frage – ohne Rechenweg.')


def _key(kind: str | None, answer: str) -> str:
    text = answer.strip().lower().rstrip('.')
    if kind == 'number':
        return text.replace(',', '.')
    return re.sub(r'\s+', ' ', text)


def solve_voted(llm, model: str, messages: list[dict], *, think: bool = True, stop=None, max_drafts: int = 3) -> ReasoningResult:
    """Unabhängige Lösungen (mit Denkschritt), bis zwei übereinstimmen – Mehrheitsentscheid statt Selbstbewertung.
    Höchstens drei Modellaufrufe. Stimmen keine zwei überein, wird das offen gesagt."""
    question = next((m.get('content', '') for m in reversed(messages) if m.get('role') == 'user'), '')
    kind = requested_shape(question)
    answers: list[str] = []
    counts: dict[str, int] = {}
    for _ in range(max_drafts):
        if stop is not None and stop.is_set():
            break
        reply = llm.chat(model, messages + [{'role': 'system', 'content': VOTE_PROMPT}], think=think,
                         num_predict=6000 if think else 900, timeout=300, temperature=0.6 if think else 0.3)
        content = strip_think(reply.content).strip()
        if not content:
            continue
        final = shape(kind, content, question) if kind else content
        answers.append(final)
        key = _key(kind, final)
        counts[key] = counts.get(key, 0) + 1
        if counts[key] >= 2:
            return ReasoningResult(final, (answers[0], answers[-1]), len(counts) > 1, len(answers))
        if kind is None and len(answers) == 1 and max_drafts >= 1:
            # Freitext lässt sich nicht abstimmen: eine sorgfältige Antwort genügt.
            return ReasoningResult(final, (final, final), False, 1)
    if not answers:
        raise ValueError('Leere Antwort im Denkmodus')
    if len(answers) >= 2 and kind is not None:
        note = ' (Unsicher: Meine Lösungswege kamen zu unterschiedlichen Ergebnissen.)'
        return ReasoningResult(answers[-1] + ('' if kind in ('number', 'yesno', 'time', 'word') else note),
                               (answers[0], answers[-1]), True, len(answers))
    return ReasoningResult(answers[-1], (answers[0], answers[-1]), False, len(answers))
