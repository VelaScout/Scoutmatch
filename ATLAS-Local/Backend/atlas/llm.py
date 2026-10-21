"""Anbindung an lokale Modelle über Ollama: Chat mit Werkzeugen, Streaming, Embeddings, Router.

Nur die lokale Adresse 127.0.0.1 wird benutzt; Proxy-Einstellungen werden ignoriert, damit
keine Anfrage versehentlich ins Internet geht. Cloud-Modelle von Ollama (Name endet auf
"-cloud" oder ":cloud") sind gesperrt.
"""
from __future__ import annotations

import json
import os
import re
import threading
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field

BASE = os.environ.get('ATLAS_OLLAMA_URL', 'http://127.0.0.1:11434')
HTTP = urllib.request.build_opener(urllib.request.ProxyHandler({}))
MODEL_PATTERN = re.compile(r'^[a-z0-9][a-z0-9._-]{0,60}(:[a-z0-9._-]{1,40})?$')
# Bevorzugte Reihenfolge – vom Router auf die tatsächlich installierten Modelle angewendet.
CHAT_PREFERENCE = ['qwen3:4b-instruct-2507-q4_K_M', 'qwen3:4b', 'qwen3:8b']
AGENT_PREFERENCE = ['qwen3:8b', 'qwen3:14b', 'qwen3:4b-instruct-2507-q4_K_M', 'qwen3:4b']
VISION_PREFERENCE = ['gemma3:4b', 'qwen2.5vl:7b', 'gemma3:12b', 'llava:7b', 'minicpm-v']
EMBED_PREFERENCE = ['qwen3-embedding:0.6b', 'nomic-embed-text', 'nomic-embed-text:latest', 'mxbai-embed-large']


class ModelError(Exception):
    pass


def is_local_model(name: str) -> bool:
    return bool(isinstance(name, str) and MODEL_PATTERN.match(name) and 'cloud' not in name)


@dataclass
class Reply:
    content: str = ''
    tool_calls: list = field(default_factory=list)
    metrics: dict = field(default_factory=dict)


class Ollama:
    def __init__(self, base: str = BASE, opener=None):
        self.base = base.rstrip('/')
        self.opener = opener or HTTP
        self._tags: tuple[float, list[str]] = (0.0, [])
        self._lock = threading.Lock()

    def _post(self, path: str, payload: dict, timeout: float):
        request = urllib.request.Request(self.base + path, data=json.dumps(payload).encode(),
                                         headers={'Content-Type': 'application/json'})
        return self.opener.open(request, timeout=timeout)

    def installed(self, refresh: bool = False) -> list[str]:
        with self._lock:
            stamp, names = self._tags
            if not refresh and names and time.monotonic() - stamp < 30:
                return names
        try:
            with self.opener.open(self.base + '/api/tags', timeout=3) as response:
                data = json.load(response)
            names = [m.get('name', '') for m in data.get('models', []) if is_local_model(m.get('name', ''))]
        except (OSError, ValueError):
            names = []
        with self._lock:
            self._tags = (time.monotonic(), names)
        return names

    def pick(self, preference: list[str], wanted: str | None = None) -> str | None:
        names = self.installed()
        if wanted and wanted in names:
            return wanted
        for name in preference:
            if name in names:
                return name
        chat = [n for n in names if 'embed' not in n]
        return chat[0] if chat else None

    def chat(self, model: str, messages: list[dict], tools: list[dict] | None = None, *, think: bool = False,
             num_ctx: int = 8192, num_predict: int = 1024, temperature: float = 0.3, json_mode: bool = False,
             timeout: float = 180, stop=None) -> Reply:
        if not is_local_model(model):
            raise ModelError('Nur lokale Modelle sind erlaubt.')
        payload = {'model': model, 'messages': messages, 'stream': False, 'think': think, 'keep_alive': '30m',
                   'options': {'num_ctx': num_ctx, 'num_predict': num_predict, 'temperature': temperature}}
        if tools:
            payload['tools'] = tools
        if json_mode:
            payload['format'] = 'json'
        started = time.monotonic()
        try:
            with self._post('/api/chat', payload, timeout) as response:
                data = json.load(response)
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                raise ModelError(f'Modell {model} fehlt in Ollama.') from exc
            body = exc.read().decode('utf-8', 'replace')[:300]
            if 'does not support tools' in body:
                raise ModelError(f'Modell {model} unterstützt keine Werkzeuge.') from exc
            raise ModelError(f'Ollama-Fehler {exc.code}: {body}') from exc
        if data.get('error'):
            raise ModelError(str(data['error'])[:300])
        message = data.get('message') or {}
        content = strip_think(message.get('content') or '')
        calls = []
        for call in message.get('tool_calls') or []:
            function = call.get('function') or {}
            args = function.get('arguments') or {}
            if isinstance(args, str):
                try:
                    args = json.loads(args)
                except ValueError:
                    args = {'_raw': args}
            calls.append({'name': function.get('name', ''), 'arguments': args if isinstance(args, dict) else {}})
        if not calls:
            calls = parse_text_tool_calls(content)
            if calls:
                content = ''
        duration = (data.get('eval_duration') or 0) / 1e9
        metrics = {'total_s': round(time.monotonic() - started, 2),
                   'prompt_tokens': data.get('prompt_eval_count'), 'tokens': data.get('eval_count'),
                   'tokens_per_s': round(data.get('eval_count', 0) / duration, 1) if duration else None,
                   'load_s': round((data.get('load_duration') or 0) / 1e9, 2)}
        return Reply(content.strip(), calls, metrics)

    def stream(self, model: str, messages: list[dict], *, num_ctx: int = 8192, num_predict: int = 700,
               temperature: float = 0.4, timeout: float = 90, stop=None):
        """Liefert Textstücke; filtert <think>-Blöcke heraus."""
        if not is_local_model(model):
            raise ModelError('Nur lokale Modelle sind erlaubt.')
        payload = {'model': model, 'messages': messages, 'stream': True, 'think': False, 'keep_alive': '30m',
                   'options': {'num_ctx': num_ctx, 'num_predict': num_predict, 'temperature': temperature}}
        thinking = ThinkFilter()
        with self._post('/api/chat', payload, timeout) as response:
            for raw in response:
                if stop is not None and stop.is_set():
                    return
                if not raw.strip():
                    continue
                part = json.loads(raw)
                if part.get('error'):
                    raise ModelError(str(part['error'])[:300])
                text = thinking.feed((part.get('message') or {}).get('content', ''))
                if text:
                    yield text
                if part.get('done'):
                    tail = thinking.feed('', final=True)
                    if tail:
                        yield tail
                    if part.get('done_reason') == 'length':
                        yield ' …'
                    return
        raise ModelError('Ollama hat die Antwort unvollständig beendet.')

    def see(self, images: list[bytes], prompt: str, timeout: float = 180) -> str | None:
        """Bildanalyse mit einem lokalen Bildmodell; None, wenn keines installiert ist."""
        import base64
        names = self.installed()
        model = next((m for m in VISION_PREFERENCE if m in names), None)
        if not model:
            return None
        message = {'role': 'user', 'content': prompt + '\nAntworte auf Deutsch, kurz und sachlich.',
                   'images': [base64.b64encode(i).decode() for i in images]}
        return self.chat(model, [message], num_predict=600, timeout=timeout).content

    def embed(self, model: str, texts: list[str], timeout: float = 30) -> list[list[float]] | None:
        if not texts:
            return []
        try:
            with self._post('/api/embed', {'model': model, 'input': texts, 'keep_alive': '30m'}, timeout) as response:
                data = json.load(response)
            vectors = data.get('embeddings')
            return vectors if isinstance(vectors, list) and len(vectors) == len(texts) else None
        except (OSError, ValueError):
            return None


def strip_think(text: str) -> str:
    return re.sub(r'(?s)<think>.*?</think>', '', text).replace('<think>', '').replace('</think>', '')


def parse_text_tool_calls(content: str) -> list[dict]:
    """Manche kleinen Modelle schreiben Werkzeugaufrufe als Text (<tool_call>{…}</tool_call>)."""
    calls = []
    for raw in re.findall(r'(?s)<tool_call>\s*(\{.*?\})\s*</tool_call>', content or ''):
        try:
            data = json.loads(raw)
        except ValueError:
            continue
        if isinstance(data, dict) and isinstance(data.get('name'), str):
            args = data.get('arguments') or {}
            calls.append({'name': data['name'], 'arguments': args if isinstance(args, dict) else {}})
    return calls


class ThinkFilter:
    """Unterdrückt <think>-Blöcke auch dann, wenn sie über mehrere Stream-Stücke verteilt sind."""

    def __init__(self):
        self.buffer = ''
        self.hidden = False

    def feed(self, text: str, final: bool = False) -> str:
        self.buffer += text
        output = ''
        while self.buffer:
            marker = '</think>' if self.hidden else '<think>'
            pos = self.buffer.find(marker)
            if pos >= 0:
                if not self.hidden:
                    output += self.buffer[:pos]
                self.buffer = self.buffer[pos + len(marker):]
                self.hidden = not self.hidden
                continue
            keep = 0
            if not final:
                for n in range(1, min(len(marker), len(self.buffer) + 1)):
                    if self.buffer.endswith(marker[:n]):
                        keep = n
            segment = self.buffer[:-keep] if keep else self.buffer
            if not self.hidden:
                output += segment
            self.buffer = self.buffer[-keep:] if keep else ''
            break
        return output


# ---------------------------------------------------------------------------
# Router: Welche Art von Anfrage ist das?
# ---------------------------------------------------------------------------

# Wortanfänge, die auf eine Aufgabe mit Werkzeugen hindeuten („erstell“ passt auf erstelle, erstellen …).
AGENT_STEMS = [
    'öffne', 'starte', 'erstell', 'erzeug', 'leg an', 'lege an', 'speicher', 'schreib mir', 'schreibe eine', 'lösch',
    'verschieb', 'kopier', 'benenn', 'such', 'recherch', 'google', 'finde', 'lies ', 'lese', 'analysier', 'fasse',
    'zusammenfass', 'ordner', 'datei', 'pdf', 'excel', 'tabelle', 'kalender', 'termin', 'erinner', 'mail', 'e-mail',
    'nachricht', 'spotify', 'musik', 'spiel ', 'timer', 'wecker', 'kurzbefehl', 'terminal', 'befehl', 'projekt',
    'fehler', 'bug', 'behebe', 'repariere', 'teste', 'build', 'kompilier', 'bildschirm', 'screenshot', 'akku',
    'speicherplatz', 'systeminfo', 'internet', 'webseite', 'website', 'safari', 'browser', 'neueste', 'aktuell',
    'wetter', 'merk dir', 'vergiss', 'open ', 'create', 'search', 'delete', 'file', 'folder', 'calendar', 'email',
]
AGENT_HINTS = re.compile(r'\b(' + '|'.join(re.escape(stem) for stem in AGENT_STEMS) + ')', re.I)
MULTI_STEP = re.compile(r'\b(und dann|danach|anschließend|schritt für schritt|step by step|plane|then|after that)\b', re.I)
ACTION_VERBS = re.compile(r'\b(öffne|erstell\w*|speicher\w*|lösch\w*|such\w*|teste?|behebe|repariere|untersuche|'
                          r'analysier\w*|schreib(?:e|en|t)?|kopier\w*|verschieb\w*|sende|schick\w*|installier\w*|baue?|'
                          r'fasse?|prüfe?|aktualisier\w*|open|create|fix|test|build|search)\b', re.I)


CORRECTION = re.compile(r'^(nein|falsch|stimmt nicht|nicht so|ich meinte|eigentlich|korrektur)\b|'
                        r'\b(ab jetzt|ab sofort|in zukunft|künftig|immer wenn|bitte immer|bitte nie|nenn mich|sprich mich)\b', re.I)
ENGLISH_WORDS = set('the and is are what how why can could would you your please with this that for of to in on my me '
                    'do does show open create find search tell about which when where who'.split())
GERMAN_WORDS = set('der die das und ist sind was wie warum kannst du dein bitte mit dies für von zu im auf mein mir '
                   'zeig öffne erstelle finde suche sag über welche wann wo wer ich nicht ein eine'.split())


def language_of(text: str) -> str:
    """'en' oder 'de' – einfache, schnelle Erkennung über häufige Wörter (Standard: Deutsch)."""
    words = re.findall(r"[a-zäöüß']+", (text or '').lower())
    english = sum(w in ENGLISH_WORDS for w in words)
    german = sum(w in GERMAN_WORDS for w in words)
    return 'en' if english >= 2 and english > german * 1.5 else 'de'


def is_correction(text: str) -> bool:
    return bool(CORRECTION.search(re.sub(r'^\[Kontext:[^\]]*\]\s*', '', text or '').strip()))


def route(text: str, has_tools: bool = True) -> str:
    """'chat' (direkt antworten), 'agent' (Werkzeuge) oder 'plan' (mehrstufige Aufgabe)."""
    if not has_tools:
        return 'chat'
    stripped = re.sub(r'^\[Kontext:[^\]]*\]\s*', '', text or '').strip()
    if stripped.lower().startswith(('aufgabe:', 'task:', 'agent:')):
        return 'plan'
    if is_correction(stripped):
        return 'agent'
    if not AGENT_HINTS.search(stripped):
        return 'chat'
    # Planen kostet eine zusätzliche Modellrunde – nur bei echten mehrstufigen Aufträgen.
    verbs = {m.lower()[:5] for m in ACTION_VERBS.findall(stripped)}
    if len(verbs) >= 3 or (MULTI_STEP.search(stripped) and len(verbs) >= 2):
        return 'plan'
    return 'agent'
