"""Gedächtnis-Abruf und Gesprächszusammenfassungen.

Die Erinnerungen selbst verwaltet die native App (SwiftData, im Gedächtnis-Fenster sichtbar,
korrigier- und löschbar). Das Backend bekommt bei jeder Anfrage die Liste und wählt die
Einträge aus, die zur aktuellen Frage passen:

1. semantisch über ein lokales Embedding-Modell (falls in Ollama installiert),
2. sonst lexikalisch (Wortüberschneidung mit Wortstämmen).

Embeddings werden in SQLite zwischengespeichert (Schlüssel: Hash des Textes); geänderte oder
gelöschte Erinnerungen fallen dadurch automatisch heraus. Das ist Abruf von gespeichertem
Wissen – kein Training der Modellgewichte.
"""
from __future__ import annotations

import hashlib
import math
import re
import sqlite3
import struct
from collections.abc import Callable

STOPWORDS = set('''der die das ein eine einer eines einem einen und oder aber ich du er sie es wir ihr mich mir dich dir
uns euch sich ist sind war waren bin bist sein hat habe haben hatte wird werden wurde mit von zu zum zur für auf in im an
am bei aus nach über unter vor wie was wer wo wann warum welche welcher welches nicht kein keine noch schon auch nur
sehr mal bitte dass the a an and or of to in on for is are was be it this that with my me you your what how'''.split())


def words(text: str) -> set[str]:
    tokens = re.findall(r'[a-zäöüß0-9]+', text.lower())
    return {t[:6] for t in tokens if t not in STOPWORDS and len(t) > 2}


def cosine(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    norm = math.sqrt(sum(x * x for x in a)) * math.sqrt(sum(y * y for y in b))
    return dot / norm if norm else 0.0


def pack(vector: list[float]) -> bytes:
    return struct.pack(f'<{len(vector)}f', *vector)


def unpack(blob: bytes) -> list[float]:
    return list(struct.unpack(f'<{len(blob) // 4}f', blob))


def normalized(text: str) -> str:
    text = re.sub(r'^\[[^\]]*\]\s*', '', text or '')
    return re.sub(r'[^a-zäöüß0-9 ]', '', text.lower()).strip()


def jaccard(a: str, b: str) -> float:
    left, right = words(a), words(b)
    return len(left & right) / len(left | right) if left and right else 0.0


class MemoryIndex:
    def __init__(self, connect: Callable[[], sqlite3.Connection],
                 embed: Callable[[str, list[str]], list[list[float]] | None] | None = None):
        self.connect = connect
        self.embed = embed
        with self.connect() as db:
            db.execute('CREATE TABLE IF NOT EXISTS embeddings (hash TEXT PRIMARY KEY, model TEXT, vector BLOB)')
            db.execute('CREATE TABLE IF NOT EXISTS summaries (hash TEXT PRIMARY KEY, content TEXT, created_at TEXT)')

    @staticmethod
    def key(text: str) -> str:
        return hashlib.sha256(text.encode()).hexdigest()

    def vectors(self, texts: list[str], model: str) -> list[list[float]] | None:
        if not self.embed or not texts:
            return None
        keys = [self.key(model + '\n' + t) for t in texts]
        found: dict[str, list[float]] = {}
        with self.connect() as db:
            for start in range(0, len(keys), 500):
                chunk = keys[start:start + 500]
                marks = ','.join('?' * len(chunk))
                for k, blob in db.execute(f'SELECT hash, vector FROM embeddings WHERE hash IN ({marks})', chunk):
                    found[k] = unpack(blob)
        missing = [(k, t) for k, t in zip(keys, texts) if k not in found]
        if missing:
            fresh = self.embed(model, [t for _, t in missing])
            if fresh is None:
                return None
            with self.connect() as db:
                db.executemany('INSERT OR REPLACE INTO embeddings(hash, model, vector) VALUES (?,?,?)',
                               [(k, model, pack(v)) for (k, _), v in zip(missing, fresh)])
            found.update({k: v for (k, _), v in zip(missing, fresh)})
        return [found[k] for k in keys]

    def relevant(self, query: str, memories: list[str], limit: int = 8, model: str = '') -> tuple[list[str], str]:
        """Die passendsten Erinnerungen und die genutzte Methode ('semantisch'/'lexikalisch'/'alle')."""
        memories = [m.strip() for m in memories if isinstance(m, str) and m.strip()][:500]
        if len(memories) <= limit:
            return memories, 'alle'
        if model:
            vectors = self.vectors([query] + memories, model)
            if vectors:
                q, rest = vectors[0], vectors[1:]
                ranked = sorted(zip(memories, rest), key=lambda item: cosine(q, item[1]), reverse=True)
                # Persönliche Grundeinstellungen (Anrede, Vorlieben) immer behalten.
                chosen = [m for m, _ in ranked[:limit]]
                return self._with_preferences(chosen, memories, limit), 'semantisch'
        query_words = words(query)
        scored = sorted(memories, key=lambda m: len(words(m) & query_words), reverse=True)
        chosen = [m for m in scored[:limit] if words(m) & query_words]
        return self._with_preferences(chosen, memories, limit), 'lexikalisch'

    @staticmethod
    def _with_preferences(chosen: list[str], memories: list[str], limit: int) -> list[str]:
        preferences = [m for m in memories if m.lower().startswith(('[vorliebe', '[präferenz', '[preference', '[einstellung'))]
        for item in preferences[:3]:
            if item not in chosen:
                chosen.append(item)
        return chosen[:limit + 3]

    def compare(self, content: str, memories: list[str], model: str = '') -> tuple[str, str | None]:
        """('duplicate'|'similar'|'new', passende vorhandene Erinnerung)."""
        target = normalized(content)
        best, best_score = None, 0.0
        for memory in memories:
            if normalized(memory) == target:
                return 'duplicate', memory
            score = jaccard(content, memory)
            if score > best_score:
                best, best_score = memory, score
        if model and memories:
            vectors = self.vectors([content] + memories, model)
            if vectors:
                scored = [(cosine(vectors[0], v), m) for v, m in zip(vectors[1:], memories)]
                semantic, memory = max(scored)
                # Bedeutungsnähe allein ist nie ein Duplikat: „wohnt in Berlin“ und „wohnt in Hamburg“
                # liegen semantisch dicht beieinander, widersprechen sich aber. Dann entscheidet das Modell.
                if semantic >= 0.82 and best_score < 0.8:
                    best, best_score = memory, max(best_score, 0.5)
        if best_score >= 0.8:
            return 'duplicate', best
        if best_score >= 0.4:
            return 'similar', best
        return 'new', None

    # -- Zusammenfassungen langer Gespräche ----------------------------------
    def summary(self, turns: list[dict], summarize: Callable[[str], str]) -> str:
        transcript = '\n'.join(f'{"Nutzer" if t["role"] == "user" else "Atlas"}: {t["content"][:1200]}' for t in turns)
        key = self.key('summary\n' + transcript)
        with self.connect() as db:
            row = db.execute('SELECT content FROM summaries WHERE hash=?', (key,)).fetchone()
        if row:
            return row[0]
        text = summarize(transcript).strip()
        if text:
            with self.connect() as db:
                db.execute("INSERT OR REPLACE INTO summaries(hash, content, created_at) VALUES (?,?,datetime('now'))",
                           (key, text))
        return text
