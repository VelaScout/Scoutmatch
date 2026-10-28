"""Optional local two-pass reasoning for complex questions; never claims correctness."""
from __future__ import annotations
import re

# Conservative opt-in by task phrasing: routine chat remains streamed and fast.
_COMPLEX = re.compile(r'\b(?:analysier\w*|begründe\w*|beweise\w*|widerlege\w*|vergleiche\w*|'
                      r'komplex\w*|mehrstufig\w*|schritt.für.schritt|denk\w*.*gründlich|'
                      r'analyze|prove|critically|step.by.step|reason through)\b', re.I)

_NUMBER = re.compile(r'\d+(?:[.,]\d+)?|\b(?:doppelt|dreimal|viermal|halb|hälfte|drittel|viertel)\b', re.I)
_ASK = re.compile(r'\b(?:wie viele?|wie hoch|wie alt|wie groß|wie lange?|wie weit|wann|welche zahl|um wie viel|'
                  r'how many|how much|how old|how long)\b', re.I)
_LOGIC = re.compile(r'\b(?:folgt daraus|zwingend|widersprüch\w*|wer ist am \w+|kann diese aussage|lüg\w*|'
                    r'setzt die reihe fort|welcher wochentag|wahr sein|logisch|rätsel)\b', re.I)


def is_reasoning_task(text: str) -> bool:
    """Textaufgaben (mehrere Zahlen + Rechenfrage) und Logikfragen: hier lohnt der Denkschritt."""
    t = text or ''
    if _LOGIC.search(t):
        return True
    return bool(_ASK.search(t)) and len(_NUMBER.findall(t)) >= 2


def should_deliberate(text: str) -> bool:
    return bool(_COMPLEX.search(text or ''))

def answer(llm, model: str, messages: list[dict], *, stop=None) -> str:
    """Produce a local draft then challenge its assumptions before responding.

    Does not disclose hidden chain-of-thought, execute tools, or guarantee factuality.
    Errors propagate so callers do not mistake failure for a valid response.
    """
    if stop is not None and stop.is_set():
        return ''
    draft = llm.chat(model, messages + [{'role': 'system', 'content':
        'Entwirf eine sachliche Antwort. Benenne Annahmen und Unsicherheit. Erfinde keine Quellen. '
        'Schreibe keine internen Denkprotokolle.'}],
        num_predict=900, timeout=120).content
    if stop is not None and stop.is_set():
        return ''
    if not draft.strip():
        raise ValueError('Leere erste Modellantwort')
    final = llm.chat(model, messages + [
        {'role': 'assistant', 'content': draft},
        {'role': 'user', 'content': 'Prüfe deine letzte Antwort kritisch auf Rechenfehler, unbelegte '
         'Behauptungen, Widersprüche und übersehene Einschränkungen. Antworte danach mit einer '
         'verbesserten, klaren Endantwort. Keine erfundenen Quellen, keine internen Denkprotokolle.'}
    ], num_predict=1100, timeout=120).content
    if not final.strip():
        raise ValueError('Leere überprüfte Modellantwort')
    return final
