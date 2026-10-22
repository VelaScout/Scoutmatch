"""Code-Werkstatt: ATLAS ändert seinen eigenen Code – nur isoliert, getestet, freigegeben und rücksetzbar.

Regeln (fest eingebaut, nicht abschaltbar):
- Änderungen entstehen in einer KOPIE des Backends; der laufende Code bleibt unberührt.
- Die komplette Testsuite muss in der Kopie bestehen. Sonst wird die Kopie verworfen.
- Tests dürfen nicht weniger werden und nicht übersprungen werden (gezählt, ohne Modell).
- Änderungen an Sicherheitsdateien (Berechtigungen, Pfadregeln, Sandbox, Freigaben, Werkstatt selbst)
  werden als „sicherheitsrelevant“ markiert und brauchen eine zusätzliche Bestätigung.
- Übernommen wird nur nach Freigabe – mit Sicherung aller betroffenen Dateien. Schlägt die Prüfung
  nach der Übernahme fehl, wird automatisch zurückgesetzt. Jede Übernahme bleibt rücksetzbar.
- Tests der Kopie laufen auf dem Mac in sandbox-exec (kein Netzwerk, Schreiben nur in der Kopie).
  Ohne Betriebssystem-Sandbox laufen sie nur, wenn das ausdrücklich erlaubt ist (Entwicklung/Tests).
"""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import tempfile
from collections.abc import Callable
from pathlib import Path

from .approvals import Approvals
from .learning import now
from .llm import ModelError

SCHEMA = '''CREATE TABLE IF NOT EXISTS code_changes (
    id INTEGER PRIMARY KEY, title TEXT NOT NULL, files TEXT NOT NULL, status TEXT NOT NULL, security_relevant INTEGER NOT NULL,
    test_output TEXT NOT NULL DEFAULT '', proposal_id INTEGER, backup TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL)'''
EDITABLE = re.compile(r'^(atlas/[a-z_]+\.py|tests/[a-z_]+\.py|web/[a-z_.]+|personality\.txt)$')
PROTECTED = {'atlas/tools.py', 'atlas/skills.py', 'atlas/skill_harness.py', 'atlas/approvals.py', 'atlas/workshop.py',
             'atlas/evolution.py', 'atlas/server.py', 'atlas/agent.py'}
IGNORE = shutil.ignore_patterns('__pycache__', '*.pyc', '.venv', 'venv', '*.db', '.git')
SUGGEST = """Du verbesserst den Python-Code des Assistenten ATLAS. Problem: {problem}
Ändere so wenig wie möglich. Sicherheitsprüfungen, Bestätigungen und Tests dürfen NICHT entfernt oder abgeschwächt werden.
Antworte nur mit JSON: {{"title": "kurze Beschreibung", "edits": [{{"file": "atlas/…py", "old": "exakter alter Text",
"new": "neuer Text"}}]}}

Dateien:
{files}"""


class WorkshopError(ValueError):
    pass


def count_tests(root: Path) -> tuple[int, int]:
    """(Anzahl Testfunktionen, Anzahl skip-Stellen) – ohne den Code auszuführen."""
    tests = skips = 0
    for path in (root / 'tests').glob('*.py'):
        text = path.read_text(encoding='utf-8', errors='replace')
        tests += len(re.findall(r'^\s*def test_\w+', text, re.M))
        skips += len(re.findall(r'\bskip(Test|If|Unless|\b)|@unittest\.skip|expectedFailure', text))
    return tests, skips


class Workshop:
    def __init__(self, connect: Callable, source: Path, base: Path, approvals: Approvals,
                 test_command: list[str] | None = None, verify: Callable[[Path], str] | None = None,
                 allow_unsandboxed: bool = False, llm=None, timeout: float = 900):
        self.connect = connect
        self.source = source.resolve()
        self.base = base
        self.approvals = approvals
        self.test_command = test_command or [sys.executable, '-m', 'unittest', 'discover', '-s', 'tests']
        self.verify = verify or self._import_check
        self.allow_unsandboxed = allow_unsandboxed
        self.llm = llm
        self.timeout = timeout
        with self.connect() as db:
            db.execute(SCHEMA)
        approvals.register('code', self._apply_from_proposal)

    # -- Vorschlag in isolierter Kopie ---------------------------------------------------------------
    def propose(self, title: str, edits: list[dict]) -> dict:
        files = self._check_edits(edits)
        security = any(f in PROTECTED or f.startswith('tests/') for f in files)
        with tempfile.TemporaryDirectory(prefix='atlas-werkstatt-') as temp:
            work = Path(temp) / 'Backend'
            shutil.copytree(self.source, work, ignore=IGNORE)
            before = count_tests(work)
            for edit in edits:
                path = work / edit['file']
                text = path.read_text(encoding='utf-8') if path.exists() else ''
                if edit.get('old'):
                    if text.count(edit['old']) != 1:
                        return self._record(title, files, 'verworfen', security, f'Alter Text in {edit["file"]} nicht eindeutig gefunden.')
                    text = text.replace(edit['old'], edit['new'])
                elif path.exists():
                    return self._record(title, files, 'verworfen', security, f'{edit["file"]} existiert – „old“ fehlt.')
                else:
                    text = edit['new']
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding='utf-8')
            after = count_tests(work)
            if after[0] < before[0] or after[1] > before[1]:
                return self._record(title, files, 'verworfen', security,
                                    f'Tests dürfen nicht entfernt oder übersprungen werden ({before} → {after}).')
            ok, output = self._run_tests(work)
            if not ok:
                return self._record(title, files, 'verworfen', security, output)   # Kopie wird mit dem Temp-Ordner gelöscht
            contents = {f: (work / f).read_text(encoding='utf-8') for f in files}
        change = self._record(title, files, 'getestet', security, output)
        package = self.base / 'pending' / str(change['id'])
        package.mkdir(parents=True, exist_ok=True)
        (package / 'files.json').write_text(json.dumps(contents, ensure_ascii=False), encoding='utf-8')
        proposal = self.approvals.propose('code', f'Code-Änderung: {title}', {
            'change_id': change['id'], 'files': files, 'tests': output.splitlines()[-3:]}, security_relevant=security)
        with self.connect() as db:
            db.execute('UPDATE code_changes SET proposal_id=? WHERE id=?', (proposal, change['id']))
        return {**change, 'proposal': proposal}

    def suggest(self, problem: str, files: list[str], model: str) -> dict:
        """Lässt das lokale Modell eine Änderung vorschlagen – sie durchläuft danach propose()."""
        if self.llm is None:
            raise WorkshopError('Kein Modell verfügbar.')
        listing = '\n\n'.join(f'### {f}\n' + (self.source / f).read_text(encoding='utf-8')[:12000]
                              for f in files if EDITABLE.match(f) and (self.source / f).is_file())
        try:
            reply = self.llm.chat(model, [{'role': 'user', 'content': SUGGEST.format(problem=problem, files=listing)}],
                                  json_mode=True, num_predict=3000, num_ctx=16384, timeout=900)
            spec = json.loads(reply.content or '{}')
        except (ModelError, ValueError) as exc:
            return {'status': 'fehlgeschlagen', 'error': f'Keine verwertbare Antwort: {exc}'}
        if not isinstance(spec.get('edits'), list) or not spec['edits']:
            return {'status': 'fehlgeschlagen', 'error': 'Keine Änderungen vorgeschlagen.'}
        try:
            return self.propose(str(spec.get('title') or problem)[:120], spec['edits'])
        except WorkshopError as exc:
            return {'status': 'verworfen', 'error': str(exc)}

    def _check_edits(self, edits) -> list[str]:
        if not isinstance(edits, list) or not 1 <= len(edits) <= 20:
            raise WorkshopError('1 bis 20 Änderungen erwartet.')
        files = []
        for edit in edits:
            if not isinstance(edit, dict) or not isinstance(edit.get('file'), str) or not isinstance(edit.get('new'), str):
                raise WorkshopError('Jede Änderung braucht file und new.')
            if not EDITABLE.match(edit['file']) or '..' in edit['file']:
                raise WorkshopError(f'Datei nicht änderbar: {edit["file"]}')
            if edit['file'] not in files:
                files.append(edit['file'])
        return files

    def _run_tests(self, work: Path) -> tuple[bool, str]:
        private = Path(tempfile.mkdtemp(prefix='atlas-werkstatt-home-'))
        env = {'PATH': '/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin', 'HOME': str(private), 'TMPDIR': str(private),
               'ATLAS_DATA_DIR': str(private / 'data'), 'PYTHONPYCACHEPREFIX': str(private / 'pycache'), 'LANG': 'de_DE.UTF-8'}
        command = list(self.test_command)
        if shutil.which('sandbox-exec'):
            # Netzwerk nur zu localhost (die Tests nutzen lokale Testserver), Schreiben nur in Kopie und Temp.
            profile = ('(version 1)(allow default)(deny network*)(allow network* (local ip "localhost:*"))'
                       '(allow network* (remote ip "localhost:*"))(allow network* (remote unix-socket))(deny file-write*)'
                       f'(allow file-write* (subpath "{work.resolve()}") (subpath "{private.resolve()}") '
                       '(subpath "/private/var/folders") (literal "/dev/null"))')
            command = ['sandbox-exec', '-p', profile] + command
        elif not self.allow_unsandboxed:
            shutil.rmtree(private, ignore_errors=True)
            return False, 'Keine Betriebssystem-Sandbox verfügbar – Tests von Code-Änderungen laufen nur auf dem Mac.'
        try:
            done = subprocess.run(command, cwd=work, env=env, capture_output=True, text=True, timeout=self.timeout)
            output = (done.stdout + done.stderr)[-5000:]
            ok = done.returncode == 0 and bool(re.search(r'^OK', output, re.M))
        except subprocess.TimeoutExpired:
            ok, output = False, f'Zeitlimit ({self.timeout:.0f} s) überschritten.'
        finally:
            shutil.rmtree(private, ignore_errors=True)
        return ok, output

    def _record(self, title: str, files: list[str], status: str, security: bool, output: str) -> dict:
        with self.connect() as db:
            change = db.execute('INSERT INTO code_changes(title, files, status, security_relevant, test_output, created_at, '
                                'updated_at) VALUES (?,?,?,?,?,?,?)', (title[:200], json.dumps(files), status, int(security),
                                                                       output[-5000:], now(), now())).lastrowid
        return {'id': change, 'status': status, 'security_relevant': security, 'output': output[-1500:]}

    # -- Übernahme (nur nach Freigabe), Prüfung, Rücksetzen -----------------------------------------
    def _apply_from_proposal(self, detail: dict) -> str:
        return self.apply(detail['change_id'])

    def apply(self, change_id: int) -> str:
        with self.connect() as db:
            row = db.execute('SELECT status FROM code_changes WHERE id=?', (change_id,)).fetchone()
        if not row or row[0] != 'getestet':
            raise WorkshopError('Änderung ist nicht getestet.')
        contents = json.loads((self.base / 'pending' / str(change_id) / 'files.json').read_text(encoding='utf-8'))
        backup = self.base / 'backups' / f'{change_id}'
        backup.mkdir(parents=True, exist_ok=True)
        manifest = {}
        for name in contents:
            current = self.source / name
            manifest[name] = current.exists()
            if current.exists():
                (backup / name).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(current, backup / name)
        (backup / 'manifest.json').write_text(json.dumps(manifest), encoding='utf-8')
        try:
            for name, text in contents.items():
                (self.source / name).parent.mkdir(parents=True, exist_ok=True)
                (self.source / name).write_text(text, encoding='utf-8')
            problem = self.verify(self.source)
        except Exception as exc:  # noqa: BLE001
            problem = f'{type(exc).__name__}: {exc}'
        if problem:
            self._restore(backup)
            self._set(change_id, 'zurueckgesetzt', str(backup))
            raise WorkshopError(f'Prüfung nach Übernahme fehlgeschlagen, automatisch zurückgesetzt: {problem[-500:]}')
        self._set(change_id, 'aktiv', str(backup))
        return 'Übernommen und geprüft. Wird mit dem nächsten Neustart von ATLAS wirksam; jederzeit rücksetzbar.'

    def rollback(self, change_id: int) -> str:
        with self.connect() as db:
            row = db.execute('SELECT status, backup, proposal_id FROM code_changes WHERE id=?', (change_id,)).fetchone()
        if not row or row[0] != 'aktiv':
            raise WorkshopError('Nur aktive Änderungen können zurückgesetzt werden.')
        self._restore(Path(row[1]))
        self._set(change_id, 'zurueckgesetzt', row[1])
        if row[2]:
            self.approvals.mark(row[2], 'zurueckgesetzt', 'Vom Nutzer zurückgesetzt.')
        return 'Vorheriger Stand wiederhergestellt. Wirksam nach dem nächsten Neustart von ATLAS.'

    def _restore(self, backup: Path) -> None:
        manifest = json.loads((backup / 'manifest.json').read_text(encoding='utf-8'))
        for name, existed in manifest.items():
            target = self.source / name
            if existed:
                shutil.copy2(backup / name, target)
            elif target.exists():
                target.unlink()       # neu angelegte Datei wieder entfernen

    def _set(self, change_id: int, status: str, backup: str) -> None:
        with self.connect() as db:
            db.execute('UPDATE code_changes SET status=?, backup=?, updated_at=? WHERE id=?', (status, backup, now(), change_id))

    @staticmethod
    def _import_check(root: Path) -> str:
        with tempfile.TemporaryDirectory(prefix='atlas-check-') as temp:
            done = subprocess.run([sys.executable, '-c', 'import atlas.server, atlas.agent, atlas.tools'], cwd=root,
                                  capture_output=True, text=True, timeout=60,
                                  env={'PATH': '/usr/bin:/bin', 'PYTHONDONTWRITEBYTECODE': '1',
                                       'TMPDIR': temp, 'ATLAS_DATA_DIR': temp})
            return '' if done.returncode == 0 else (done.stderr or done.stdout)[-1500:]


    def list(self) -> list[dict]:
        with self.connect() as db:
            cursor = db.execute('SELECT id, title, files, status, security_relevant, substr(test_output, -400), proposal_id, '
                                'created_at, updated_at FROM code_changes ORDER BY id DESC LIMIT 100')
            names = ['id', 'title', 'files', 'status', 'security_relevant', 'test_output', 'proposal_id', 'created_at', 'updated_at']
            items = [dict(zip(names, row)) for row in cursor.fetchall()]
        for item in items:
            item['files'] = json.loads(item['files'])
        return items
