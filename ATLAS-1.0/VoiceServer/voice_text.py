"""Textvorbereitung für flüssigere Sprachausgabe, ohne externe Pakete."""
import re


def spoken_text(text: str) -> str:
    """Remove visual Markdown and URLs that TTS otherwise reads as punctuation.

    Does not translate or invent content. Limits size at the API boundary.
    """
    text = re.sub(r'```[\s\S]*?```', ' Ein Codebeispiel ist in der Textansicht verfügbar. ', text)
    text = re.sub(r'\[([^\]]+)\]\(https?://[^)]+\)', r'\1', text)
    text = re.sub(r'https?://\S+', ' Link in der Textansicht. ', text)
    text = re.sub(r'(?m)^\s{0,3}(?:#{1,6}\s+|[-*+]\s+|\d+[.)]\s+)', '', text)
    text = re.sub(r'[*_`~]+', '', text)
    return re.sub(r'\s+', ' ', text).strip()
