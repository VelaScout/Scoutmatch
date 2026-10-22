"""Betriebssystem-Sandbox (macOS sandbox-exec) für selbst entwickelte Fähigkeiten und die Code-Werkstatt.

- Schreiben nur in ausdrücklich genannten Ordnern, Netzwerk gesperrt (wahlweise nur localhost).
- Bevor ein Profil benutzt wird, prüft ATLAS es einmal tatsächlich: Lässt es den Start zu, sperrt es
  Schreiben außerhalb, erlaubt es Schreiben innerhalb? Ein ungültiges oder wirkungsloses Profil wird
  nie still benutzt – dann gibt es eine verständliche Fehlermeldung statt rätselhafter Testfehler.
- Mehrere Profil-Varianten werden der Reihe nach probiert (Syntax unterscheidet sich je macOS-Version).
- Auf Systemen ohne sandbox-exec (Linux, Tests) gibt available() False zurück; die Aufrufer
  entscheiden dann selbst (Fähigkeiten: Python-Schutz; Code-Werkstatt: verweigert).
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

_LOCK = threading.Lock()
_CHOSEN: dict[str, int] = {}          # Netzwerkart → Index der funktionierenden Variante
_PROBLEM: dict[str, str] = {}


class SandboxError(RuntimeError):
    pass


def _binary() -> str:
    return shutil.which('sandbox-exec') or 'sandbox-exec'


def available() -> bool:
    # Innerhalb einer Sandbox lässt macOS keine zweite zu (z. B. Testsuite in der Code-Werkstatt);
    # dort schützt bereits die äußere Sandbox.
    return shutil.which('sandbox-exec') is not None and not os.environ.get('ATLAS_IN_SANDBOX')


def _quote(path: Path) -> str:
    return json.dumps(str(Path(path).resolve()))


def _variants(writable: list[Path], network: str) -> list[str]:
    paths = ' '.join(f'(subpath {_quote(p)})' for p in writable)
    files = f'(deny file-write*)(allow file-write* {paths} (literal "/dev/null") (literal "/dev/dtracehelper"))'
    if network == 'none':
        nets = ['(deny network*)']
    else:   # nur lokale Testserver
        nets = ['(deny network*)(allow network* (remote ip "localhost:*"))(allow network* (local ip "localhost:*"))',
                '(deny network-outbound (remote ip))(deny network-inbound (local ip))',
                '(deny network-outbound (remote tcp "*:*"))(allow network-outbound (remote tcp "localhost:*"))']
    return [f'(version 1)(allow default){net}{files}' for net in nets]


NET_PROBE = """
import json, socket
def tcp(host, port):
    try:
        socket.create_connection((host, port), timeout=2).close(); return True
    except OSError:
        return False
local = None
try:
    server = socket.socket(); server.bind(('127.0.0.1', 0)); server.listen(1)
    local = tcp('127.0.0.1', server.getsockname()[1]); server.close()
except OSError:
    local = False
print(json.dumps({'local': local, 'remote': tcp('1.1.1.1', 443)}))
"""


def _probe(profile: str, inside: Path, outside: Path, network: str = 'none') -> str:
    """'' wenn das Profil funktioniert, sonst eine Beschreibung des Problems."""
    def run(script: str) -> subprocess.CompletedProcess:
        return subprocess.run([_binary(), '-p', profile, '/bin/sh', '-c', script], capture_output=True,
                              text=True, timeout=15, env={'PATH': '/usr/bin:/bin'})
    try:
        start = run('exit 0')
        if start.returncode != 0:
            return f'Profil wird nicht angenommen: {(start.stderr or start.stdout).strip()[:300]}'
        if run(f'echo ok > {json.dumps(str(inside / "probe.txt"))}').returncode != 0:
            return 'Profil verhindert Schreiben im erlaubten Ordner.'
        run(f'echo x > {json.dumps(str(outside / "probe.txt"))}')
        if (outside / 'probe.txt').exists():
            return 'Profil verhindert Schreiben außerhalb NICHT.'
        net = subprocess.run([_binary(), '-p', profile, sys.executable, '-I', '-c', NET_PROBE], capture_output=True,
                             text=True, timeout=20, env={'PATH': '/usr/bin:/bin', 'TMPDIR': str(inside)})
        try:
            reach = json.loads(net.stdout.strip().splitlines()[-1])
        except (ValueError, IndexError):
            return f'Netzwerkprüfung nicht möglich: {(net.stderr or net.stdout).strip()[-300:]}'
        if reach['remote']:
            return 'Profil verhindert Internetzugriff NICHT.'
        if network == 'localhost' and not reach['local']:
            return 'Profil sperrt auch localhost (für lokale Tests nötig).'
    except (OSError, subprocess.TimeoutExpired) as exc:
        return f'sandbox-exec nicht nutzbar: {exc}'
    return ''


def _choose(network: str) -> int:
    with _LOCK:
        if network in _CHOSEN:
            return _CHOSEN[network]
        if network in _PROBLEM:
            raise SandboxError(_PROBLEM[network])
        problems = []
        with tempfile.TemporaryDirectory(prefix='atlas-sb-in-') as inside, \
                tempfile.TemporaryDirectory(prefix='atlas-sb-out-') as outside:
            for index, profile in enumerate(_variants([Path(inside)], network)):
                problem = _probe(profile, Path(inside).resolve(), Path(outside).resolve(), network)
                if not problem:
                    _CHOSEN[network] = index
                    return index
                problems.append(problem)
        _PROBLEM[network] = 'macOS-Sandbox (sandbox-exec) funktioniert hier nicht wie erwartet: ' + ' | '.join(problems)[:800]
        raise SandboxError(_PROBLEM[network])


def wrap(command: list[str], writable: list[Path], network: str = 'none') -> list[str]:
    """Befehl in die geprüfte Sandbox einpacken. Wirft SandboxError, wenn keine Variante sicher funktioniert."""
    if not available():
        raise SandboxError('sandbox-exec ist auf diesem System nicht vorhanden.')
    index = _choose(network)
    return [_binary(), '-p', _variants(writable, network)[index]] + list(command)


def reset() -> None:
    """Prüfergebnis vergessen (Tests, oder nach einem macOS-Update)."""
    with _LOCK:
        _CHOSEN.clear()
        _PROBLEM.clear()


def status() -> dict:
    """Für Diagnose und Mac-Testlauf: welche Variante greift, oder warum keine."""
    if not available():
        return {'available': False}
    result = {'available': True}
    for network in ('none', 'localhost'):
        try:
            result[network] = f'Variante {_choose(network) + 1}'
        except SandboxError as exc:
            result[network] = str(exc)
    return result
