"""Schutz von Zugangsdaten: Passwörter, PINs, Schlüssel, Karten- und Kontonummern werden nie gespeichert.

contains_secret(): erkennt Zugangsdaten in einem Text (ohne Modell, bewusst eher vorsichtig).
redact(): ersetzt erkannte Werte durch „[entfernt]“ – für Erfahrungen, Aufgabenjournal und Protokolle.
"""
from __future__ import annotations

import re

LABELLED = re.compile(
    r'\b(passwort|kennwort|password|passcode|pin|tan|puk|geheimzahl|zugangsdaten|login|api[ -]?key|api[ -]?schlüssel|'
    r'access[ -]?token|token|secret|geheimnis|private[ -]?key|sicherheitscode|cvv|cvc)\b'
    r'(\s+(für|von|zu|des|der|vom|meines|meiner|for|of)(\s+[\w.@-]+){1,3}?)?'
    r'\s*(ist|lautet|heißt|=|:|is)\s*["„“\']?(?P<value>[^\s"„“\']{3,})', re.I)
RAW_KEYS = re.compile(r'\b(sk-[A-Za-z0-9_-]{16,}|sk-ant-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|'
                      r'xox[abpr]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{30,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)')
IBAN = re.compile(r'\b[A-Z]{2}\d{2}(?:\s?[A-Z0-9]{4}){3,7}(?:\s?[A-Z0-9]{1,3})?\b')
CARD = re.compile(r'\b(?:\d[ -]?){13,19}\b')


def _luhn(number: str) -> bool:
    digits = [int(d) for d in re.sub(r'\D', '', number)]
    if not 13 <= len(digits) <= 19:
        return False
    total = 0
    for index, digit in enumerate(reversed(digits)):
        if index % 2:
            digit = digit * 2 - 9 if digit > 4 else digit * 2
        total += digit
    return total % 10 == 0


def findings(text: str) -> list[str]:
    found = []
    if LABELLED.search(text or ''):
        found.append('Zugangsdaten')
    if RAW_KEYS.search(text or ''):
        found.append('Schlüssel/Token')
    if any(_luhn(m.group()) for m in CARD.finditer(text or '')):
        found.append('Kartennummer')
    if IBAN.search(text or ''):
        found.append('Kontonummer (IBAN)')
    return found


def contains_secret(text: str) -> bool:
    return bool(findings(text))


def redact(text: str) -> str:
    if not text:
        return text
    text = LABELLED.sub(lambda m: m.group(0)[:m.start('value') - m.start()] + '[entfernt]', text)
    text = RAW_KEYS.sub('[entfernt]', text)
    text = CARD.sub(lambda m: '[entfernt]' if _luhn(m.group()) else m.group(), text)
    return IBAN.sub('[entfernt]', text)


REFUSAL = ('Passwörter, PINs, Schlüssel sowie Karten- und Kontonummern speichere ich nie im Gedächtnis. '
           'Dafür ist der macOS-Schlüsselbund (App „Passwörter“) da.')
