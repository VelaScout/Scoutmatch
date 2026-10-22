"""Optionales Cloud-Modell (Claude über die offizielle Anthropic-API) – nur nach ausdrücklicher Aktivierung.

Grundsätze:
- Standard ist AUS. Ohne Einschalten in der App und ohne gespeicherten Schlüssel verlässt nichts den Mac.
- Pro Auftrag ausdrücklich: „Cloud: …“ / „Mit Claude: …“ am Satzanfang (oder Schalter in der App).
- Vor der Übertragung zeigt ATLAS, WAS den Mac verlässt (Zeichen, Nachrichten, Erinnerungen,
  Werkzeugergebnisse) und was es höchstens kostet; ohne Zustimmung wird nichts gesendet –
  außer Sie haben eine ausdrückliche Dauerfreigabe gesetzt.
- Kosten werden aus den tatsächlich gemeldeten Token berechnet (Listenpreise, US-Dollar) und
  gegen ein Monatslimit geprüft. Ist das Limit erreicht, wird nichts mehr gesendet.
- Der API-Schlüssel liegt im macOS-Schlüsselbund, nie in Datenbank, Einstellungen oder Protokollen.
Ein großes Cloud-Modell ist leistungsfähiger als das lokale 4B-Modell – das ist der Grund für die Option.
Lokal bleibt der Standard.
"""
from __future__ import annotations

import re
import shutil
import subprocess
from collections.abc import Callable
from datetime import datetime, timezone

from .llm import ModelError, Reply

# Listenpreise US-$ pro 1 Mio. Token (Anthropic, Stand 06.10.2026). Andere Modelle: Preis unbekannt.
PRICES = {'claude-opus-5-5': (4.00, 20.00), 'claude-sonnet-5-5': (2.00, 10.00), 'claude-haiku-5-5': (0.10, 0.50),
          'claude-opus-5': (5.00, 25.00), 'claude-opus-4-8': (5.00, 25.00)}
MODELS = ('claude-opus-5-5', 'claude-sonnet-5-5', 'claude-haiku-5-5')
DEFAULTS = {'enabled': False, 'model': 'claude-opus-5-5', 'monthly_limit_usd': 5.0, 'always_allow': False,
            'effort': 'medium', 'mode': 'lokal'}
LOCAL_PREFIX = re.compile(r'^\s*(?:atlas[,!.]?\s*)?(?:lokal|local)\s*[:,]\s*', re.I)
MODE_SWITCH = re.compile(r'^\s*(?:atlas[,!.]?\s*)?(?:bitte\s+)?(?:wechsle|schalte|geh|gehe|switch)\w*\s+(?:in\s+den\s+|auf\s+(?:den\s+)?|to\s+)?'
                         r'(?P<mode>cloud|lokalen|lokal|local)[\s-]*(?:modus|mode|betrieb)?\b', re.I)
PREFIX = re.compile(r'^\s*(?:atlas[,!.]?\s*)?(?:cloud|mit claude|frag claude|claude|mit der cloud)\s*[:,]\s*', re.I)
SERVICE, ACCOUNT = 'ATLAS Cloud', 'anthropic'
KEY_FORMAT = re.compile(r'sk-ant-[A-Za-z0-9_-]{20,300}')
SCHEMA = '''CREATE TABLE IF NOT EXISTS cloud_usage (
    id INTEGER PRIMARY KEY, created_at TEXT NOT NULL, model TEXT NOT NULL, input_tokens INTEGER NOT NULL,
    output_tokens INTEGER NOT NULL, cost_usd REAL, note TEXT NOT NULL DEFAULT '')'''


class CloudError(Exception):
    pass


class Keychain:
    """macOS-Schlüsselbund über das Systemwerkzeug `security`. Der Schlüssel geht über stdin, nicht über
    die Befehlszeile (dort wäre er in der Prozessliste sichtbar)."""

    def available(self) -> bool:
        return shutil.which('security') is not None

    def get(self) -> str | None:
        if not self.available():
            return None
        done = subprocess.run(['security', 'find-generic-password', '-s', SERVICE, '-a', ACCOUNT, '-w'],
                              capture_output=True, text=True, timeout=10)
        return (done.stdout.strip() or None) if done.returncode == 0 else None

    def set(self, key: str) -> None:
        if not self.available():
            raise CloudError('Schlüsselbund nicht verfügbar (nur auf dem Mac).')
        if not KEY_FORMAT.fullmatch(key or ''):
            raise CloudError('Das sieht nicht wie ein Anthropic-API-Schlüssel aus.')
        command = f'add-generic-password -U -s "{SERVICE}" -a "{ACCOUNT}" -w "{key}"\n'
        done = subprocess.run(['security', '-i'], input=command, capture_output=True, text=True, timeout=10)
        if done.returncode != 0 or self.get() != key:
            raise CloudError('Schlüssel konnte nicht im Schlüsselbund gespeichert werden.')

    def delete(self) -> None:
        if self.available():
            subprocess.run(['security', 'delete-generic-password', '-s', SERVICE, '-a', ACCOUNT],
                           capture_output=True, text=True, timeout=10)


def cost(model: str, input_tokens: int, output_tokens: int) -> float | None:
    if model not in PRICES:
        return None
    price_in, price_out = PRICES[model]
    return (input_tokens * price_in + output_tokens * price_out) / 1_000_000


class Cloud:
    def __init__(self, connect: Callable, settings: Callable[[], dict], save: Callable[[dict], None],
                 keychain=None, client_factory=None):
        self.connect = connect
        self.read_settings = settings
        self.save_settings = save
        self.keychain = keychain or Keychain()
        self.client_factory = client_factory
        with self.connect() as db:
            db.execute(SCHEMA)

    # -- Einstellungen und Status -------------------------------------------------------------------
    def settings(self) -> dict:
        stored = self.read_settings() or {}
        merged = {**DEFAULTS, **{k: v for k, v in stored.items() if k in DEFAULTS}}
        if merged['model'] not in MODELS:
            merged['model'] = DEFAULTS['model']
        return merged

    def update(self, **changes) -> dict:
        clean = {}
        for key, value in changes.items():
            if key in ('enabled', 'always_allow'):
                if not isinstance(value, bool):
                    raise ValueError(f'{key}: ja/nein erwartet')
            elif key == 'model':
                if value not in MODELS:
                    raise ValueError('Unbekanntes Cloud-Modell.')
            elif key == 'monthly_limit_usd':
                if not isinstance(value, (int, float)) or isinstance(value, bool) or not 0 <= value <= 500:
                    raise ValueError('Monatslimit: 0 bis 500 US-$.')
            elif key == 'mode':
                if value not in ('lokal', 'cloud'):
                    raise ValueError('Modus: lokal oder cloud.')
            elif key == 'effort':
                if value not in ('low', 'medium', 'high'):
                    raise ValueError('Gründlichkeit: low, medium oder high.')
            else:
                raise ValueError(f'Unbekannte Einstellung: {key}')
            clean[key] = value
        self.save_settings({**self.settings(), **clean})
        return self.status()

    def spent_this_month(self) -> float:
        month = datetime.now(timezone.utc).strftime('%Y-%m')
        with self.connect() as db:
            return db.execute("SELECT coalesce(sum(cost_usd),0) FROM cloud_usage WHERE substr(created_at,1,7)=?",
                              (month,)).fetchone()[0]

    def status(self) -> dict:
        config = self.settings()
        has_key = bool(self.keychain.get())
        problem = ('' if config['enabled'] and has_key and self.spent_this_month() < config['monthly_limit_usd'] else
                   'ausgeschaltet' if not config['enabled'] else 'kein API-Schlüssel hinterlegt' if not has_key else
                   'Monatslimit erreicht')
        return {**config, 'has_key': has_key, 'keychain': self.keychain.available(), 'ready': not problem,
                'problem': problem, 'spent_usd': round(self.spent_this_month(), 4),
                'prices': {m: PRICES[m] for m in MODELS}}

    def requested(self, text: str, flag: bool = False) -> tuple[bool, str]:
        """(Cloud gewünscht?, Text ohne Präfix). Im Cloud-Modus gilt jede Anfrage als Cloud-Anfrage,
        außer sie beginnt mit „Lokal:“."""
        if LOCAL_PREFIX.match(text):
            return False, LOCAL_PREFIX.sub('', text, count=1).strip()
        if PREFIX.match(text):
            return True, PREFIX.sub('', text, count=1).strip()
        return bool(flag) or self.settings()['mode'] == 'cloud', text

    def switch(self, text: str) -> str | None:
        """Sprachbefehl „Wechsle in den Cloud-Modus / lokalen Modus“. Gibt die Antwort zurück oder None."""
        match = MODE_SWITCH.match(text)
        if not match:
            return None
        wanted = 'cloud' if match['mode'].lower() == 'cloud' else 'lokal'
        if wanted == 'cloud':
            status = self.status()
            if not status['enabled'] or not status['has_key']:
                return ('Der Cloud-Modus ist noch nicht freigegeben. Bitte in den Einstellungen unter „Cloud-Modell“ '
                        'einschalten und einen API-Schlüssel hinterlegen. Bis dahin arbeite ich lokal.')
            self.update(mode='cloud')
            note = '' if status['always_allow'] else ' Vor jeder Übertragung frage ich dich und zeige, welche Daten den Mac verlassen.'
            return (f'Cloud-Modus aktiv ({status["model"]}). Monatslimit {status["monthly_limit_usd"]:.2f} US-$, '
                    f'bisher {status["spent_usd"]:.2f} US-$.{note} Mit „Lokal: …“ bleibt eine einzelne Anfrage auf dem Mac.')
        self.update(mode='lokal')
        return 'Lokaler Modus aktiv. Es verlässt nichts mehr den Mac, solange du nicht „Cloud: …“ sagst.'


    def preview(self, messages: list[dict]) -> str:
        """Verständliche Beschreibung dessen, was den Mac verlässt."""
        config = self.settings()
        system = messages[0]['content'] if messages and messages[0]['role'] == 'system' else ''
        chat = [m for m in messages if m['role'] in ('user', 'assistant')]
        chars = sum(len(str(m.get('content') or '')) for m in messages)
        tokens = chars // 3 + 2000
        worst = cost(config['model'], tokens * 4, 4000 * 4)          # grob: bis zu 4 Runden
        memories = 'mit gespeicherten Erinnerungen' if 'Erinnerung' in system or 'Über den Nutzer' in system else ''
        return (f'An Anthropic ({config["model"]}) gehen: {len(chat)} Gesprächsnachrichten, Anweisungen {memories}, '
                f'insgesamt ca. {chars} Zeichen; dazu die Ergebnisse der Werkzeuge in dieser Aufgabe '
                f'(z. B. gelesene Dateien). Geschätzte Kosten höchstens ca. {worst:.2f} US-$ '
                f'(diesen Monat bisher {self.spent_this_month():.2f} von {config["monthly_limit_usd"]:.2f} US-$).')

    def client(self):
        if self.client_factory:
            return self.client_factory()
        key = self.keychain.get()
        if not key:
            raise CloudError('Kein API-Schlüssel im Schlüsselbund.')
        try:
            import anthropic
        except ImportError as exc:
            raise CloudError('Cloud-Modul fehlt (AKTUALISIEREN.command ausführen).') from exc
        return anthropic.Anthropic(api_key=key, max_retries=2, timeout=300)

    def llm(self, log=None) -> 'CloudLLM':
        status = self.status()
        if not status['ready']:
            raise CloudError(f'Cloud nicht verfügbar: {status["problem"]}.')
        return CloudLLM(self, status['model'], status['effort'], log)

    def record(self, model: str, input_tokens: int, output_tokens: int, note: str = '') -> float | None:
        value = cost(model, input_tokens, output_tokens)
        with self.connect() as db:
            db.execute('INSERT INTO cloud_usage(created_at, model, input_tokens, output_tokens, cost_usd, note) VALUES (?,?,?,?,?,?)',
                       (datetime.now(timezone.utc).isoformat(), model, input_tokens, output_tokens, value, note))
        return value


class CloudLLM:
    """Gleiche Schnittstelle wie llm.Ollama (für den Agenten), aber mit Claude. Zählt Token und Kosten."""

    def __init__(self, cloud: Cloud, model: str, effort: str, log=None):
        self.cloud = cloud
        self.model = model
        self.effort = effort
        self.log = log or (lambda *_: None)
        self.calls = 0
        self.input_tokens = 0
        self.output_tokens = 0
        self.cost_usd = 0.0
        self.unknown_price = False
        self._client = None

    # Schnittstelle wie Ollama
    def agent_model(self, wanted=None) -> str:
        return self.model

    def fast_model(self, wanted=None) -> str:
        return self.model

    def reasoning_only(self, model: str) -> bool:
        return False

    def pick(self, names):
        return None

    def summary(self) -> str:
        price = 'Preis teils unbekannt' if self.unknown_price else f'ca. {self.cost_usd:.4f} US-$'.replace('.', ',')
        return (f'Cloud ({self.model}): {self.calls} Anfrage(n), {self.input_tokens} Token gesendet, '
                f'{self.output_tokens} Token empfangen, {price}.')

    def chat(self, model: str, messages: list[dict], tools: list[dict] | None = None, *, json_mode: bool = False,
             num_predict: int = 1024, timeout: float = 180, **_) -> Reply:
        import anthropic
        if self.cloud.spent_this_month() >= self.cloud.settings()['monthly_limit_usd']:
            raise ModelError('Cloud-Monatslimit erreicht – es wurde nichts gesendet.')
        system, converted = convert(messages, json_mode)
        params = {'model': self.model, 'max_tokens': max(4096, min(16000, num_predict * 4)), 'messages': converted,
                  'output_config': {'effort': self.effort}, 'betas': ['server-side-fallback-2026-07-01'],
                  'fallbacks': 'default'}
        if system:
            params['system'] = system
        if tools:
            params['tools'] = [{'name': t['function']['name'], 'description': t['function'].get('description', '')[:1000],
                                'input_schema': t['function'].get('parameters') or {'type': 'object', 'properties': {}}}
                               for t in tools]
        try:
            self._client = self._client or self.cloud.client()
            response = self._client.with_options(timeout=max(30.0, timeout)).beta.messages.create(**params)
        except CloudError as exc:
            raise ModelError(str(exc)) from exc
        except anthropic.AuthenticationError as exc:
            raise ModelError('Cloud: API-Schlüssel ungültig.') from exc
        except anthropic.RateLimitError as exc:
            raise ModelError('Cloud: zu viele Anfragen – bitte kurz warten.') from exc
        except anthropic.APIStatusError as exc:
            raise ModelError(f'Cloud-Fehler {exc.status_code}.') from exc
        except anthropic.APIConnectionError as exc:
            raise ModelError('Cloud nicht erreichbar (Internet?).') from exc
        self._account(response)
        if response.stop_reason == 'refusal':
            return Reply('Das Cloud-Modell hat diese Anfrage aus Sicherheitsgründen abgelehnt.', [], {})
        text = ''.join(block.text for block in response.content if block.type == 'text')
        calls = [{'name': block.name, 'arguments': dict(block.input or {}), 'id': block.id}
                 for block in response.content if block.type == 'tool_use']
        reply = Reply(text, calls, {'cloud': True})
        # Originalblöcke (inkl. Denkblöcken) unverändert für die nächste Runde aufheben – die API verlangt das.
        reply.raw = [block.to_dict() for block in response.content]
        return reply

    def _account(self, response) -> None:
        usage = response.usage
        hops = [(it.model or self.model, it.input_tokens, it.output_tokens) for it in (usage.iterations or [])
                if getattr(it, 'input_tokens', None) is not None] or [(response.model, usage.input_tokens, usage.output_tokens)]
        self.calls += 1
        for model, sent, received in hops:
            self.input_tokens += sent
            self.output_tokens += received
            value = self.cloud.record(str(model), sent, received, 'fallback' if str(model) != self.model else '')
            if value is None:
                self.unknown_price = True
            else:
                self.cost_usd += value


def convert(messages: list[dict], json_mode: bool = False) -> tuple[str, list[dict]]:
    """Ollama-Nachrichten → Anthropic-Format. Werkzeugergebnisse werden den tool_use-IDs der Reihe nach
    zugeordnet; Assistenten-Antworten der Cloud werden unverändert (mit Denkblöcken) wiederholt."""
    system_parts, out, pending = [], [], []
    for message in messages:
        role = message.get('role')
        if role == 'system':
            if not out:
                system_parts.append(str(message.get('content') or ''))
            else:
                out.append({'role': 'user', 'content': f'[Hinweis des Systems] {message.get("content")}'})
            continue
        if role == 'tool':
            tool_id = pending.pop(0) if pending else None
            block = ({'type': 'tool_result', 'tool_use_id': tool_id, 'content': str(message.get('content') or '')}
                     if tool_id else {'type': 'text', 'text': f'[Werkzeugergebnis] {message.get("content")}'})
            if out and out[-1]['role'] == 'user' and isinstance(out[-1]['content'], list):
                out[-1]['content'].append(block)
            else:
                out.append({'role': 'user', 'content': [block]})
            continue
        if role == 'assistant':
            raw = message.get('_raw')
            if raw:
                out.append({'role': 'assistant', 'content': raw})
                pending = [b['id'] for b in raw if b.get('type') == 'tool_use']
            else:
                text = str(message.get('content') or '').strip()
                calls = message.get('tool_calls') or []
                if calls:      # ohne Original-IDs (z. B. lokale Runde) als Text wiedergeben
                    text += '\n' + '\n'.join(f'[Werkzeugaufruf {c["function"]["name"]}]' for c in calls)
                    pending = []
                if text.strip():
                    out.append({'role': 'assistant', 'content': text.strip()})
            continue
        if pending:     # Werkzeugergebnisse fehlen (sollte nicht vorkommen): ehrlich als Fehler schließen
            out.append({'role': 'user', 'content': [{'type': 'tool_result', 'tool_use_id': i, 'content': 'Nicht ausgeführt.',
                                                     'is_error': True} for i in pending]})
            pending = []
        content = str(message.get('content') or '')
        if out and out[-1]['role'] == 'user' and isinstance(out[-1]['content'], list):
            out[-1]['content'].append({'type': 'text', 'text': content})
        else:
            out.append({'role': 'user', 'content': content})
    if json_mode:
        system_parts.append('Antworte ausschließlich mit gültigem JSON, ohne weiteren Text.')
    if not out or out[0]['role'] != 'user':
        out.insert(0, {'role': 'user', 'content': '(Fortsetzung)'})
    return '\n\n'.join(p for p in system_parts if p), out

