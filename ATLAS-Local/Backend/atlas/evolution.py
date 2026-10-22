"""ATLAS – Learning & Evolution: Planer für Lernaufträge und Zusammenführung aller Lernbausteine.

Bausteine (je eigenes Modul):
- Experience Memory, Task Outcome Evaluator, Reflection, User Preference Learning → learning.py
- Skill Registry + Skill Development Sandbox → skills.py / skill_harness.py
- Semantic Knowledge Retrieval / Wissensaufbau → knowledge.py
- Improvement Engine → improvement.py
- Code-Werkstatt (Versioning & Rollback des eigenen Codes) → workshop.py
- Human Approval System → approvals.py
- Improvement Scheduler → hier

Der Planer:
- Aufträge des Nutzers („lerne …“) laufen im Hintergrund, sobald ATLAS nicht gerade antwortet.
- Eigenständige Lernzyklen (Fehleranalyse, Verbesserungsvorschläge) NUR, wenn eingeschaltet.
- Pausierbar; Tageslimit für Rechenzeit der Zyklen; Netzwerk abschaltbar. Kosten: keine – es werden
  ausschließlich lokale Modelle und frei zugängliche Webseiten genutzt, keine bezahlten Dienste.
- Ergebnisse werden nie still aktiviert: Alles Dauerhafte wartet auf Freigabe in der App.
"""
from __future__ import annotations

import json
import re
import threading
import time
from collections.abc import Callable
from datetime import datetime, timedelta, timezone
from pathlib import Path

from .approvals import Approvals
from .improvement import Improvement
from .knowledge import Knowledge
from .learning import Learning, now
from .skills import SkillLab
from .capabilities import existing
from .tools import SAFE, Result, Tool, ToolError, build_tools, obj, string
from .workshop import Workshop

SCHEMA = [
    '''CREATE TABLE IF NOT EXISTS evolution_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)''',
    '''CREATE TABLE IF NOT EXISTS evolution_jobs (
        id INTEGER PRIMARY KEY, kind TEXT NOT NULL, payload TEXT NOT NULL, origin TEXT NOT NULL, status TEXT NOT NULL,
        created_at TEXT NOT NULL, started_at TEXT, finished_at TEXT, seconds REAL NOT NULL DEFAULT 0,
        result TEXT NOT NULL DEFAULT '')''',
]
DEFAULTS = {'enabled': False, 'paused': False, 'max_minutes_per_day': 30, 'allow_network': True, 'cycle_hours': 6}
LIMITS = {'max_minutes_per_day': (5, 600), 'cycle_hours': (1, 168)}

LEARN_START = re.compile(r'^(?:atlas[,!.]?\s*)?(?:bitte\s+)?(?:lern|informier|eigne\s+dir|bring\s+dir|entwickle)', re.I)
TOPIC = re.compile(r'^(?:atlas[,!.]?\s*)?(?:bitte\s+)?(?:lern\w*|informier\w*\s+dich|eigne\s+dir|bring\s+dir)\b.*?'
                   r'\b(?:alles\s+)?(?:über|zum\s+thema|zu\s+dem\s+thema)\s+(?:(?:das|dem)\s+thema\s+)?(?P<topic>.+?)[\s.!?]*$', re.I)
SKILL = re.compile(r'^(?:atlas[,!.]?\s*)?(?:bitte\s+)?(?:lern\w*|bring\s+dir\s+selbst\s+bei|bring\s+dir\s+bei|'
                   r'entwickle?\s+(?:dir\s+)?(?:eine\s+)?(?:neue\s+)?fähigkeit)\b[\s,:]*(?:,?\s*wie\s+man\s+|dazu,?\s*|zu\s+)?'
                   r'(?P<what>.+?)[\s.!?]*$', re.I)
SKILL_HINT = re.compile(r'wie man|fähigkeit|\b\w+en\b\s*$|präsentation|powerpoint|pptx|word|docx|erstell|erzeug|bearbeit|umwandel|konvertier', re.I)


WANT = re.compile(r'^(?:atlas[,!.]?\s*)?(?:ich\s+(?:möchte|will|hätte\s+gern|wünsche\s+mir),?\s+dass\s+du|du\s+sollst|'
                  r'kannst\s+du\s+lernen,?)\s+(?P<what>.+?)\s*(?:kannst|können|lernst|beherrschst)?[\s.!?]*$', re.I)


def learning_intent(text: str) -> tuple[str, dict] | None:
    """Erkennt Lernaufträge ohne Modell: ('learn_topic', {...}) oder ('learn_skill', {...})."""
    stripped = text.strip()
    want = WANT.match(stripped)
    if want and len(want['what']) > 3:
        return 'learn_skill', {'description': want['what'][:300]}
    if not LEARN_START.match(stripped):
        return None
    topic = TOPIC.match(stripped)
    if topic and not re.search(r'wie man|erstell|erzeug|bearbeit|fähigkeit', stripped, re.I):
        return 'learn_topic', {'topic': topic['topic'][:200]}
    skill = SKILL.match(stripped)
    if skill and SKILL_HINT.search(skill['what']):
        return 'learn_skill', {'description': skill['what'][:300]}
    if topic:
        return 'learn_topic', {'topic': topic['topic'][:200]}
    return None


class Scheduler:
    def __init__(self, connect: Callable, busy: Callable[[], bool] = lambda: False, log=None):
        self.connect = connect
        self.busy = busy
        self.log = log or (lambda *_: None)
        self.handlers: dict[str, tuple[Callable[[dict, threading.Event], dict], bool]] = {}
        self.current: threading.Event | None = None
        self.lock = threading.Lock()
        self.thread: threading.Thread | None = None
        self.halt = threading.Event()
        with self.connect() as db:
            for statement in SCHEMA:
                db.execute(statement)
            # Nach einem Neustart: abgebrochene Läufe ehrlich als abgebrochen markieren.
            db.execute("UPDATE evolution_jobs SET status='abgebrochen', result='ATLAS wurde beendet.' WHERE status='läuft'")

    # -- Einstellungen -------------------------------------------------------------------------------
    def settings(self) -> dict:
        with self.connect() as db:
            stored = dict(db.execute('SELECT key, value FROM evolution_settings').fetchall())
        return {key: json.loads(stored[key]) if key in stored else value for key, value in DEFAULTS.items()}

    def update(self, **changes) -> dict:
        for key, value in changes.items():
            if key not in DEFAULTS:
                raise ValueError(f'Unbekannte Einstellung: {key}')
            if isinstance(DEFAULTS[key], bool):
                if not isinstance(value, bool):
                    raise ValueError(f'{key}: ja/nein erwartet')
            elif not isinstance(value, int) or isinstance(value, bool) or not LIMITS[key][0] <= value <= LIMITS[key][1]:
                raise ValueError(f'{key}: Zahl zwischen {LIMITS[key][0]} und {LIMITS[key][1]} erwartet')
        with self.connect() as db:
            db.executemany('INSERT OR REPLACE INTO evolution_settings(key, value) VALUES (?,?)',
                           [(k, json.dumps(v)) for k, v in changes.items()])
        if changes.get('paused') and self.current:
            self.current.set()          # Pause bricht den laufenden Auftrag ab
        return self.settings()

    # -- Aufträge -------------------------------------------------------------------------------------
    def register(self, kind: str, handler: Callable[[dict, threading.Event], dict], network: bool = False) -> None:
        self.handlers[kind] = (handler, network)

    def submit(self, kind: str, payload: dict, origin: str = 'nutzer') -> int:
        if kind not in self.handlers:
            raise ValueError('Unbekannte Auftragsart.')
        encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True)
        with self.connect() as db:
            same = db.execute("SELECT id FROM evolution_jobs WHERE kind=? AND payload=? AND status IN ('wartet','läuft')",
                              (kind, encoded)).fetchone()
            if same:
                return same[0]
            return db.execute('INSERT INTO evolution_jobs(kind, payload, origin, status, created_at) VALUES (?,?,?,?,?)',
                              (kind, encoded, origin, 'wartet', now())).lastrowid

    def cancel(self, job_id: int) -> bool:
        with self.connect() as db:
            status = db.execute('SELECT status FROM evolution_jobs WHERE id=?', (job_id,)).fetchone()
            if not status:
                return False
            if status[0] == 'wartet':
                db.execute("UPDATE evolution_jobs SET status='abgebrochen', finished_at=? WHERE id=?", (now(), job_id))
                return True
        if status[0] == 'läuft' and self.current:
            self.current.set()
            return True
        return False

    def used_seconds_today(self) -> float:
        today = datetime.now(timezone.utc).date().isoformat()
        with self.connect() as db:
            return db.execute("SELECT coalesce(sum(seconds),0) FROM evolution_jobs WHERE origin='zyklus' AND started_at>=?",
                              (today,)).fetchone()[0]

    def cycle(self) -> bool:
        """Startet einen eigenständigen Lernzyklus, wenn eingeschaltet und fällig."""
        config = self.settings()
        if not config['enabled'] or config['paused'] or 'analyse' not in self.handlers:
            return False
        since = (datetime.now(timezone.utc) - timedelta(hours=config['cycle_hours'])).isoformat()
        with self.connect() as db:
            recent = db.execute("SELECT 1 FROM evolution_jobs WHERE kind='analyse' AND origin='zyklus' AND created_at>=?",
                                (since,)).fetchone()
        if recent:
            return False
        self.submit('analyse', {}, origin='zyklus')
        return True

    def run_next(self) -> dict | None:
        """Führt den ältesten wartenden Auftrag aus (falls erlaubt). Gibt das Ergebnis zurück."""
        config = self.settings()
        if config['paused'] or self.busy():
            return None
        with self.lock, self.connect() as db:
            rows = db.execute("SELECT id, kind, payload, origin FROM evolution_jobs WHERE status='wartet' ORDER BY id").fetchall()
        budget = config['max_minutes_per_day'] * 60 - self.used_seconds_today()
        for job_id, kind, payload, origin in rows:
            handler, network = self.handlers.get(kind, (None, False))
            if handler is None:
                self._finish(job_id, 'fehlgeschlagen', {'error': 'Keine Ausführung für diese Art.'}, 0)
                continue
            if network and not config['allow_network']:
                self._finish(job_id, 'blockiert', {'error': 'Netzwerk für Lernaufträge ist ausgeschaltet.'}, 0)
                continue
            if origin == 'zyklus' and budget <= 0:
                continue          # Tageslimit erreicht – wartet bis morgen
            return self._execute(job_id, handler, json.loads(payload), budget if origin == 'zyklus' else None)
        return None

    def _execute(self, job_id: int, handler, payload: dict, budget: float | None) -> dict:
        stop = threading.Event()
        self.current = stop
        timer = threading.Timer(max(budget, 30), stop.set) if budget is not None else None
        if timer:
            timer.daemon = True
            timer.start()
        with self.connect() as db:
            db.execute("UPDATE evolution_jobs SET status='läuft', started_at=? WHERE id=?", (now(), job_id))
        started = time.monotonic()
        try:
            result = handler(payload, stop)
            status = 'abgebrochen' if stop.is_set() or result.get('status') == 'abgebrochen' else 'fertig'
        except Exception as exc:  # noqa: BLE001 – Fehler ehrlich festhalten
            result, status = {'error': f'{type(exc).__name__}: {exc}'[:800]}, 'fehlgeschlagen'
        finally:
            if timer:
                timer.cancel()
            self.current = None
        self._finish(job_id, status, result, time.monotonic() - started)
        self.log(f'Lernauftrag {job_id}: {status}')
        return {'id': job_id, 'status': status, 'result': result}

    def _finish(self, job_id: int, status: str, result: dict, seconds: float) -> None:
        with self.connect() as db:
            db.execute('UPDATE evolution_jobs SET status=?, result=?, seconds=?, finished_at=? WHERE id=?',
                       (status, json.dumps(result, ensure_ascii=False, default=str)[:4000], seconds, now(), job_id))

    def jobs(self, limit: int = 30) -> list[dict]:
        with self.connect() as db:
            cursor = db.execute('SELECT * FROM evolution_jobs ORDER BY id DESC LIMIT ?', (limit,))
            names = [c[0] for c in cursor.description]
            items = [dict(zip(names, row)) for row in cursor.fetchall()]
        for item in items:
            item['payload'] = json.loads(item['payload'])
            try:
                item['result'] = json.loads(item['result']) if item['result'] else {}
            except ValueError:
                pass
        return items

    # -- Hintergrund ----------------------------------------------------------------------------------
    def start(self, interval: float = 15) -> None:
        if self.thread:
            return

        def loop():
            while not self.halt.wait(interval):
                try:
                    self.cycle()
                    self.run_next()
                except Exception as exc:  # noqa: BLE001 – der Planer darf ATLAS nie beenden
                    self.log(f'Lernplaner: {exc}')
        self.thread = threading.Thread(target=loop, name='atlas-evolution', daemon=True)
        self.thread.start()

    def stop(self) -> None:
        self.halt.set()
        if self.current:
            self.current.set()


class Evolution:
    """Alle Lernbausteine zusammen – so nutzt sie der Server."""

    def __init__(self, connect: Callable, learning: Learning, llm, data: Path, source: Path,
                 search=None, fetch=None, busy: Callable[[], bool] = lambda: False, log=None,
                 model: Callable[[], str] | None = None, allow_unsandboxed_code: bool = False):
        self.learning = learning
        self.log = log or (lambda *_: None)
        self.model = model or (lambda: llm.agent_model(None))
        self.approvals = Approvals(connect)
        self.skills = SkillLab(connect, data / 'skills', self.approvals, llm, log=self.log)
        self.knowledge = Knowledge(connect, llm, search=search, fetch=fetch, log=self.log)
        self.improvement = Improvement(connect, learning, self.approvals)
        self.workshop = Workshop(connect, source, data / 'werkstatt', self.approvals, llm=llm,
                                 allow_unsandboxed=allow_unsandboxed_code)
        self.scheduler = Scheduler(connect, busy=busy, log=self.log)
        self.scheduler.register('skill', lambda p, stop: self.skills.develop(p['description'], self.model(), stop=stop))
        self.scheduler.register('topic', lambda p, stop: self.knowledge.learn(p['topic'], self.model(), stop=stop), network=True)
        self.scheduler.register('analyse', lambda p, stop: self.analyse())
        self.scheduler.register('code', lambda p, stop: self.workshop.suggest(p['problem'], p.get('files') or [], self.model()))

    def analyse(self) -> dict:
        undone = self.improvement.review()
        proposals = self.improvement.analyze()
        values = self.learning.snapshot({'skills_active': sum(1 for s in self.skills.list() if s['status'] == 'aktiv'),
                                         'skills_developed': sum(1 for s in self.skills.list() if s['status'] != 'verworfen')})
        return {'proposals': proposals, 'zurueckgenommen': undone, 'metrics': values}

    # -- Für den Agenten -------------------------------------------------------------------------------
    def intent(self, text: str):
        return learning_intent(text)

    def context_for(self, text: str) -> str:
        return self.knowledge.context_for(text)

    def tools(self, env) -> dict[str, Tool]:
        def learn_skill(description: str) -> Result:
            if not description or len(description) > 300:
                raise ToolError('Beschreibung der Fähigkeit fehlt.')
            # 1. Erst prüfen, ob es schon geht – nichts doppelt entwickeln.
            available = existing(description, {**build_tools(env), **self.skills.tools(env)})
            if available:
                return Result(True, available, verified=True, data={'existing': True})
            job = self.scheduler.submit('skill', {'description': description.strip()})
            return Result(True, f'Das kann ich noch nicht. Lernauftrag {job}: „{description.strip()}“. Mein Vorgehen: '
                                '1. passende Bibliotheken auswählen (nur geprüfte, Installation nur mit deiner Freigabe), '
                                '2. die Fähigkeit in einer abgeschotteten Testumgebung umsetzen, 3. mit eigenen Tests an echten '
                                'Dateien prüfen, 4. dir das Ergebnis im Bereich „Learning & Evolution“ zur Freigabe vorlegen. '
                                'Bis du sie freigibst, beherrsche ich sie noch nicht.',
                          verified=True, data={'job': job})

        def learn_topic(topic: str) -> Result:
            if not topic or len(topic) > 200:
                raise ToolError('Thema fehlt.')
            if not self.scheduler.settings()['allow_network']:
                return Result(False, 'Netzwerk für Lernaufträge ist ausgeschaltet (Learning & Evolution → Einstellungen).')
            job = self.scheduler.submit('topic', {'topic': topic.strip()})
            return Result(True, f'Lernauftrag {job} angenommen: „{topic.strip()}“. Ich lese Quellen, prüfe jede Aussage gegen '
                                'ihren Quelltext und speichere sie mit Quelle und Datum. Widersprüche und Lücken markiere '
                                'ich. Den Stand siehst du unter „Learning & Evolution“.', verified=True, data={'job': job})

        result = {
            'learn_skill': Tool('learn_skill', 'Neue Fähigkeit selbst entwickeln, die ATLAS noch nicht hat. Prüft zuerst, '
                                'ob sie schon vorhanden ist. Läuft im Hintergrund, wird getestet und erst nach Freigabe aktiv.',
                                obj({'description': string('Was die Fähigkeit können soll')}, ['description']),
                                learn_skill, SAFE, 'learn', 'Startet Lernauftrag'),
            'learn_topic': Tool('learn_topic', 'Wissen zu einem Thema aus Quellen aufbauen (z. B. „Unternehmensbewertung“). '
                                'Läuft im Hintergrund.', obj({'topic': string('Thema')}, ['topic']),
                                learn_topic, SAFE, 'learn', 'Startet Lernauftrag'),
        }
        result.update(self.skills.tools(env))
        return result

    # -- Für die App -----------------------------------------------------------------------------------
    def announcements(self) -> list[dict]:
        texts = []
        for item in self.approvals.pending():
            detail = item['detail']
            if item['kind'] == 'skill':
                text = (f'Ich habe eine neue Fähigkeit entwickelt und getestet: {detail["name"]} '
                        f'({detail.get("tests") or 0} Tests bestanden). Möchtest du sie aktivieren?')
            elif item['kind'] == 'package':
                text = f'Für die Fähigkeit {detail.get("for_skill")} brauche ich die Bibliothek {detail["package"]}. Darf ich sie installieren?'
            elif item['kind'] == 'hint':
                measured = detail.get('evaluation')
                note = f' (Testfälle: {measured["ohne"]:.0%} → {measured["mit"]:.0%})' if measured else ''
                text = f'Ich habe eine bessere Methode gefunden: {detail["text"]}{note} Möchtest du sie aktivieren?'
            else:
                text = (f'Ich habe eine Code-Verbesserung isoliert getestet: {item["title"]}. '
                        + ('Achtung: betrifft Sicherheitsbereiche. ' if item['security_relevant'] else '')
                        + 'Möchtest du sie übernehmen?')
            texts.append({'id': item['id'], 'kind': item['kind'], 'text': text, 'security_relevant': bool(item['security_relevant'])})
        return texts

    def overview(self) -> dict:
        return {
            'metrics': self.learning.metrics(), 'history': self.learning.history(),
            'rules': self.learning.list('rules'), 'experiences': self.learning.list('experiences', 60),
            'skills': self.skills.list(), 'topics': self.knowledge.topics(), 'hints': self.improvement.list(),
            'code_changes': self.workshop.list(), 'proposals': self.approvals.list(limit=50),
            'jobs': self.scheduler.jobs(), 'settings': self.scheduler.settings(),
            'used_minutes_today': round(self.scheduler.used_seconds_today() / 60, 1),
            'announcements': self.announcements(),
        }

    def decide(self, proposal_id: int, approved: bool, confirm_security: bool = False) -> dict:
        item = self.approvals.get(proposal_id)
        if not item:
            raise ValueError('Vorschlag nicht gefunden.')
        if approved and item['security_relevant'] and not confirm_security:
            raise ValueError('Sicherheitsrelevante Änderung: bitte ausdrücklich bestätigen.')
        return self.approvals.decide(proposal_id, approved)
