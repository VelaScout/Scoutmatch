"""Optional local two-pass reasoning for complex questions; never claims correctness."""
from __future__ import annotations
import re

# Conservative opt-in by task phrasing: routine chat remains streamed and fast.
_COMPLEX = re.compile(r'\b(?:analysier\w*|begründe\w*|beweise\w*|widerlege\w*|vergleiche\w*|'
                      r'komplex\w*|mehrstufig\w*|schritt.für.schritt|denk\w*.*gründlich|'
                      r'analyze|prove|critically|step.by.step|reason through)\b', re.I)

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
