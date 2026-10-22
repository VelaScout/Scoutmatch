"""Skill Registry und Skill-Sandbox: ATLAS entwickelt fehlende Fähigkeiten selbst – getestet und freigegeben.

Ablauf (develop):
1. Das lokale Modell schreibt eine Fähigkeit (Python-Modul mit run()) UND Tests dazu.
2. Statische Prüfung: nur erlaubte Bibliotheken, keine Shell, kein Netzwerk, keine Introspektion.
3. Tests laufen in einem eigenen, begrenzten Prozess (skill_harness.py) in einem Sandbox-Ordner.
4. Schlägt etwas fehl, bekommt das Modell die Fehlermeldung und darf nachbessern (begrenzte Versuche).
5. Fehlt eine Bibliothek, entsteht ein Installationsvorschlag – installiert wird nur nach Freigabe.
6. Bestandene Fähigkeiten warten auf Freigabe; erst dann werden sie aktiv und als Werkzeug angeboten.
7. Jede Version bleibt erhalten; zurücksetzen auf die vorige Version ist jederzeit möglich.
"""
from __future__ import annotations

import ast
import json
import re
import shutil
import subprocess
import sys
import tempfile
from collections.abc import Callable
from datetime import datetime, timezone
from pathlib import Path

from .approvals import Approvals
from .llm import ModelError
from .tools import CONFIRM, Result, Tool, ToolError, obj, string

SCHEMA = '''CREATE TABLE IF NOT EXISTS skills (
    id INTEGER PRIMARY KEY, name TEXT NOT NULL, version INTEGER NOT NULL, description TEXT NOT NULL,
    parameters TEXT NOT NULL, requirements TEXT NOT NULL, status TEXT NOT NULL, path TEXT NOT NULL,
    attempts INTEGER NOT NULL, test_output TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)'''

STANDARD_MODULES = {'json', 're', 'math', 'datetime', 'pathlib', 'csv', 'collections', 'itertools', 'statistics',
                    'decimal', 'fractions', 'textwrap', 'string', 'typing', 'dataclasses', 'enum', 'functools',
                    'operator', 'random', 'unicodedata', 'io', 'zipfile', 'html', 'unittest', 'os', 'calendar', 'uuid'}
# Bibliotheken, die eine Fähigkeit nutzen darf (Importname → pip-Paket). Installation nur nach Freigabe.
LIBRARIES = {'pptx': 'python-pptx', 'docx': 'python-docx', 'openpyxl': 'openpyxl', 'pypdf': 'pypdf',
             'PIL': 'pillow', 'fpdf': 'fpdf2', 'reportlab': 'reportlab', 'markdown': 'markdown', 'yaml': 'pyyaml'}
FORBIDDEN_NAMES = {'eval', 'exec', 'compile', '__import__', 'globals', 'locals', 'vars', 'getattr', 'setattr',
                   'delattr', 'input', 'breakpoint', 'exit', 'quit', 'memoryview', '__builtins__'}
FORBIDDEN_ATTRIBUTES = {'system', 'popen', 'spawn', 'fork', 'kill', 'remove', 'unlink', 'rmdir', 'rmtree', 'chmod',
                        'chown', 'symlink_to', 'hardlink_to', 'rename', 'putenv', 'execv', 'execve',
                        'startfile', 'removedirs', 'truncate'}

PROMPT = """Du entwickelst eine neue Fähigkeit für den lokalen Assistenten ATLAS (Python 3.10+).
Antworte NUR mit JSON: {"name": "snake_case_name", "description": "…", "parameters": {JSON-Schema eines Objekts},
"requirements": ["pptx"], "code": "…", "tests": "…"}
Regeln für "code":
- Definiere def run(args: dict, output_dir: str) -> dict. Neue Dateien NUR in output_dir anlegen.
- Rückgabe: {"ok": true, "message": "kurz, deutsch", "files": ["dateiname"]}.
- Erlaubt: Python-Standardbibliothek (json, re, math, datetime, pathlib, csv …) und: pptx, docx, openpyxl, pypdf, PIL, fpdf.
- Verboten: subprocess, socket, Netzwerk, eval/exec, Dateien löschen, Zugriff außerhalb von output_dir.
Regeln für "tests": unittest-Modul, das `import skill` nutzt, run() mit realistischen Beispieldaten aufruft
(output_dir = os.environ["ATLAS_SKILL_OUTPUT"]) und das ERGEBNIS prüft (Datei existiert, Inhalt stimmt)."""


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def check_code(source: str) -> list[str]:
    """Statische Sicherheitsprüfung. Leere Liste = in Ordnung."""
    problems = []
    try:
        tree = ast.parse(source)
    except SyntaxError as exc:
        return [f'Syntaxfehler: {exc}']
    for node in ast.walk(tree):
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            names = [alias.name for alias in node.names] if isinstance(node, ast.Import) else [node.module or '']
            for name in names:
                top = name.split('.')[0]
                if top not in STANDARD_MODULES and top not in LIBRARIES and top not in ('skill',):
                    problems.append(f'Import nicht erlaubt: {name}')
        elif isinstance(node, ast.Name) and node.id in FORBIDDEN_NAMES:
            problems.append(f'Verboten: {node.id}')
        elif isinstance(node, ast.Attribute):
            if node.attr.startswith('__') and node.attr.endswith('__') and node.attr not in ('__name__', '__init__'):
                problems.append(f'Verbotener Zugriff: {node.attr}')
            elif node.attr in FORBIDDEN_ATTRIBUTES:
                problems.append(f'Verbotene Operation: .{node.attr}')
    return sorted(set(problems))


def missing_libraries(code: str, tests: str) -> list[str]:
    import importlib.util
    needed = set()
    for source in (code, tests):
        for node in ast.walk(ast.parse(source)):
            if isinstance(node, ast.Import):
                needed.update(alias.name.split('.')[0] for alias in node.names)
            elif isinstance(node, ast.ImportFrom) and node.module:
                needed.add(node.module.split('.')[0])
    return sorted(name for name in needed if name in LIBRARIES and importlib.util.find_spec(name) is None)


def run_harness(mode: str, skill_dir: Path, output_dir: Path, arguments: dict | None = None,
                timeout: float = 120) -> dict:
    """Startet die Fähigkeit in einem eigenen, begrenzten Prozess."""
    harness = Path(__file__).with_name('skill_harness.py')
    # The child receives exactly the temp directory allowed by the OS sandbox.
    # Without TMPDIR, macOS Python falls back to /tmp, which is intentionally denied.
    with tempfile.TemporaryDirectory(prefix='atlas-skill-private-') as private:
        temp = Path(private).resolve()
        command = [sys.executable, '-I', str(harness), mode, str(skill_dir.resolve()),
                   str(output_dir.resolve()), json.dumps(arguments or {})]
        if shutil.which('sandbox-exec'):
            profile = ('(version 1)(allow default)(deny network*)(deny file-write*)'
                       f'(allow file-write* (subpath {json.dumps(str(output_dir.resolve()))}) '
                       f'(subpath {json.dumps(str(temp))}) (literal "/dev/null"))')
            command = ['sandbox-exec', '-p', profile] + command
        try:
            done = subprocess.run(command, capture_output=True, text=True, timeout=timeout,
                                  env={'PATH': '/usr/bin:/bin', 'HOME': str(output_dir.resolve()),
                                       'TMPDIR': str(temp), 'TMP': str(temp), 'TEMP': str(temp),
                                       'PYTHONDONTWRITEBYTECODE': '1', 'LANG': 'de_DE.UTF-8'})
        except subprocess.TimeoutExpired:
            return {'ok': False, 'error': f'Zeitlimit ({timeout:.0f} s) überschritten.'}
        lines = [line for line in done.stdout.splitlines() if line.startswith('{')]
        if not lines:
            return {'ok': False, 'error': (done.stderr or done.stdout or 'Keine Ausgabe')[-3000:]}
        try:
            result = json.loads(lines[-1])
        except ValueError:
            return {'ok': False, 'error': 'Fähigkeit lieferte ungültiges JSON.'}
        if not isinstance(result, dict):
            return {'ok': False, 'error': 'Fähigkeit lieferte kein Ergebnisobjekt.'}
        if done.returncode != 0:
            return {'ok': False, 'error': (done.stderr or 'Fähigkeitsprozess fehlgeschlagen.')[-3000:]}
        return result


class SkillLab:
    def __init__(self, connect: Callable, base: Path, approvals: Approvals, llm=None,
                 installer: Callable[[str], str] | None = None, log=None):
        self.connect = connect
        self.base = base
        self.approvals = approvals
        self.llm = llm
        self.installer = installer or pip_install
        self.log = log or (lambda *_: None)
        with self.connect() as db:
            db.execute(SCHEMA)
        approvals.register('skill', self._activate_from_proposal)
        approvals.register('package', lambda detail: self.installer(detail['package']))

    # -- Entwickeln ------------------------------------------------------------------------------
    def develop(self, request: str, model: str, max_attempts: int = 3, stop=None) -> dict:
        """Entwickelt eine Fähigkeit in der Sandbox. Ergebnis: Status und ggf. Vorschlags-ID."""
        if self.llm is None:
            raise ToolError('Kein Modell für die Entwicklung verfügbar.')
        messages = [{'role': 'system', 'content': PROMPT}, {'role': 'user', 'content': f'Gewünschte Fähigkeit: {request}'}]
        last_error = ''
        for attempt in range(1, max_attempts + 1):
            if stop is not None and stop.is_set():
                return {'status': 'abgebrochen'}
            try:
                reply = self.llm.chat(model, messages, json_mode=True, num_predict=3000, num_ctx=12000, timeout=600)
                spec = json.loads(reply.content)
            except (ModelError, ValueError) as exc:
                last_error = f'Ungültige Antwort: {exc}'
                messages.append({'role': 'user', 'content': f'{last_error}. Antworte nur mit gültigem JSON.'})
                continue
            problem = self._validate_spec(spec)
            if problem:
                last_error = problem
                messages += [{'role': 'assistant', 'content': reply.content[:6000]},
                             {'role': 'user', 'content': f'Abgelehnt: {problem}. Bitte korrigieren.'}]
                continue
            missing = missing_libraries(spec['code'], spec['tests'])
            if missing:
                ids = [self.approvals.propose('package', f'Bibliothek {LIBRARIES[name]} installieren',
                                              {'package': LIBRARIES[name], 'for_skill': spec['name']}) for name in missing]
                self._store(spec, 'braucht_paket', attempt, f'Fehlende Bibliotheken: {", ".join(missing)}')
                return {'status': 'braucht_paket', 'proposals': ids, 'name': spec['name']}
            version, folder = self._new_version(spec['name'])
            (folder / 'skill.py').write_text(spec['code'], encoding='utf-8')
            (folder / 'test_skill.py').write_text(spec['tests'], encoding='utf-8')
            (folder / 'skill.json').write_text(json.dumps({k: spec[k] for k in ('name', 'description', 'parameters', 'requirements')},
                                                          ensure_ascii=False, indent=2), encoding='utf-8')
            with tempfile.TemporaryDirectory(prefix='atlas-skilltest-') as output:
                result = run_harness('test', folder, Path(output))
            report = result.get('output') or result.get('error', '')
            if result.get('ok'):
                skill_id = self._store(spec, 'getestet', attempt, report, version, folder)
                proposal = self.approvals.propose('skill', f'Neue Fähigkeit: {spec["name"]} (v{version})',
                                                  {'skill_id': skill_id, 'name': spec['name'], 'version': version,
                                                   'description': spec['description'], 'tests': result.get('tests')})
                self.log(f'Fähigkeit {spec["name"]} v{version} bestanden – wartet auf Freigabe')
                return {'status': 'wartet_auf_freigabe', 'proposal': proposal, 'name': spec['name'], 'version': version,
                        'tests': result.get('tests')}
            last_error = report[-2500:]
            self._store(spec, 'verworfen', attempt, report, version, folder)
            shutil.rmtree(folder, ignore_errors=True)        # fehlgeschlagene Version wird verworfen
            messages += [{'role': 'assistant', 'content': reply.content[:6000]},
                         {'role': 'user', 'content': f'Die Tests sind fehlgeschlagen:\n{last_error}\nBitte Code oder Tests korrigieren.'}]
        return {'status': 'fehlgeschlagen', 'error': last_error[-1500:]}

    def _validate_spec(self, spec) -> str:
        if not isinstance(spec, dict):
            return 'JSON-Objekt erwartet'
        for key in ('name', 'description', 'code', 'tests'):
            if not isinstance(spec.get(key), str) or not spec[key].strip():
                return f'Feld {key} fehlt'
        if not re.fullmatch(r'[a-z][a-z0-9_]{2,40}', spec['name']):
            return 'name muss snake_case sein (3–40 Zeichen)'
        if not isinstance(spec.get('parameters'), dict):
            spec['parameters'] = {'type': 'object', 'properties': {}}
        spec.setdefault('requirements', [])
        problems = check_code(spec['code']) + [f'Tests: {p}' for p in check_code(spec['tests'])]
        if problems:
            return '; '.join(problems[:6])
        if 'def run(' not in spec['code']:
            return 'run(args, output_dir) fehlt'
        return ''

    def _new_version(self, name: str) -> tuple[int, Path]:
        with self.connect() as db:
            version = (db.execute('SELECT max(version) FROM skills WHERE name=?', (name,)).fetchone()[0] or 0) + 1
        folder = self.base / 'sandbox' / name / f'v{version}'
        folder.mkdir(parents=True, exist_ok=True)
        return version, folder

    def _store(self, spec: dict, status: str, attempts: int, output: str, version: int = 0, folder: Path | None = None) -> int:
        with self.connect() as db:
            cursor = db.execute(
                'INSERT INTO skills(name, version, description, parameters, requirements, status, path, attempts, '
                'test_output, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
                (spec['name'], version, spec['description'][:500], json.dumps(spec.get('parameters') or {}),
                 json.dumps(spec.get('requirements') or []), status, str(folder or ''), attempts, output[-4000:], now(), now()))
            return cursor.lastrowid

    # -- Freigabe, Aktivierung, Rücksetzen ---------------------------------------------------------
    def _activate_from_proposal(self, detail: dict) -> str:
        return self.activate(detail['skill_id'])

    def activate(self, skill_id: int) -> str:
        with self.connect() as db:
            row = db.execute('SELECT name, version, path, status FROM skills WHERE id=?', (skill_id,)).fetchone()
        if not row or row[3] not in ('getestet', 'archiviert'):
            raise ValueError('Diese Fähigkeit ist nicht getestet.')
        name, version, path, _ = row
        source = Path(path)
        # Vor dem Aktivieren erneut testen – nichts Ungetestetes wird aktiv.
        with tempfile.TemporaryDirectory(prefix='atlas-skilltest-') as output:
            check = run_harness('test', source, Path(output))
        if not check.get('ok'):
            raise RuntimeError('Erneuter Test fehlgeschlagen: ' + (check.get('output') or check.get('error', ''))[-500:])
        target = self.base / 'active' / name / f'v{version}'
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(source, target)
        with self.connect() as db:
            db.execute("UPDATE skills SET status='archiviert', updated_at=? WHERE name=? AND status='aktiv'", (now(), name))
            db.execute("UPDATE skills SET status='aktiv', path=?, updated_at=? WHERE id=?", (str(target), now(), skill_id))
        return f'{name} v{version} ist aktiv.'

    def rollback(self, name: str) -> str:
        """Aktuelle Version deaktivieren und die vorige (archivierte) wieder aktivieren."""
        with self.connect() as db:
            active = db.execute("SELECT id, version FROM skills WHERE name=? AND status='aktiv'", (name,)).fetchone()
            previous = db.execute("SELECT id, version FROM skills WHERE name=? AND status='archiviert' ORDER BY version DESC",
                                  (name,)).fetchone()
            if not active:
                raise ValueError('Keine aktive Version.')
            db.execute("UPDATE skills SET status='zurueckgesetzt', updated_at=? WHERE id=?", (now(), active[0]))
            if previous:
                db.execute("UPDATE skills SET status='aktiv', updated_at=? WHERE id=?", (now(), previous[0]))
        return f'{name}: v{active[1]} deaktiviert' + (f', v{previous[1]} wieder aktiv.' if previous else '.')

    def disable(self, name: str) -> None:
        with self.connect() as db:
            db.execute("UPDATE skills SET status='deaktiviert', updated_at=? WHERE name=? AND status='aktiv'", (now(), name))

    def list(self) -> list[dict]:
        with self.connect() as db:
            cursor = db.execute('SELECT id, name, version, description, status, attempts, created_at, updated_at, '
                                'substr(test_output, -600) FROM skills ORDER BY id DESC LIMIT 200')
            names = ['id', 'name', 'version', 'description', 'status', 'attempts', 'created_at', 'updated_at', 'test_output']
            return [dict(zip(names, row)) for row in cursor.fetchall()]

    # -- Registry: aktive Fähigkeiten als Werkzeuge -----------------------------------------------
    def tools(self, env) -> dict[str, Tool]:
        with self.connect() as db:
            rows = db.execute("SELECT name, version, description, parameters, path FROM skills WHERE status='aktiv'").fetchall()
        result = {}
        for name, version, description, parameters, path in rows:
            schema = json.loads(parameters) if parameters else {'type': 'object', 'properties': {}}
            properties = dict(schema.get('properties') or {})
            properties['output_folder'] = string('Ordner für die erzeugten Dateien, z. B. "~/Documents".')
            tool_name = f'skill_{name}'

            def run(skill_path=Path(path), **kwargs):
                folder = env.resolve(kwargs.pop('output_folder', None) or '~/Documents', for_write=True)
                folder.mkdir(parents=True, exist_ok=True)
                before = {p.name for p in folder.iterdir()}
                outcome = run_harness('run', skill_path, folder, kwargs)
                if not outcome.get('ok'):
                    return Result(False, 'Fähigkeit fehlgeschlagen: ' + str(outcome.get('error') or outcome.get('result'))[-800:])
                value = outcome.get('result') or {}
                created = [f for f in value.get('files') or [] if (folder / f).exists()]
                new_files = sorted({p.name for p in folder.iterdir()} - before)
                return Result(True, f"{value.get('message', 'Erledigt')} Dateien: {', '.join(new_files or created) or '–'}",
                              verified=bool(new_files or created) or not value.get('files'),
                              data={'files': [str(folder / f) for f in (new_files or created)]})
            result[tool_name] = Tool(tool_name, f'[Selbst entwickelt, v{version}] {description}',
                                     obj(properties, list(schema.get('required') or [])), run, risk=CONFIRM,
                                     category='core', label=f'Nutzt Fähigkeit {name}',
                                     describe=lambda a, n=name: f'Selbst entwickelte Fähigkeit {n} ausführen')
        return result


def pip_install(package: str) -> str:
    """Installiert eine freigegebene Bibliothek in die Atlas-Python-Umgebung (nur aus der festen Liste)."""
    if package not in LIBRARIES.values():
        raise ValueError('Paket nicht in der erlaubten Liste.')
    done = subprocess.run([sys.executable, '-m', 'pip', 'install', '--quiet', '--disable-pip-version-check', package],
                          capture_output=True, text=True, timeout=600)
    if done.returncode != 0:
        raise RuntimeError(done.stderr[-500:])
    return f'{package} installiert.'
