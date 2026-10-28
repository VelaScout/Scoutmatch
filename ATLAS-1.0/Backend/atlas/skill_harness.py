"""Ausführungsumgebung für selbst entwickelte Fähigkeiten (läuft als eigener, begrenzter Prozess).

Aufruf: python3 -I skill_harness.py test|run <skill_ordner> <ausgabe_ordner> [<argumente_json>]

Grenzen (zusätzlich zur statischen Prüfung beim Entwickeln):
- CPU-Zeit, Dateigröße und Anzahl offener Dateien begrenzt (resource.setrlimit)
- kein Netzwerk (socket wird gesperrt; auf dem Mac zusätzlich sandbox-exec)
- Schreiben nur im Ausgabeordner und im temporären Ordner
Ausgabe: genau eine JSON-Zeile auf stdout.
"""
import builtins
import io
import json
import os
import resource
import socket
import sys
import tempfile
import traceback
import unittest
from pathlib import Path


def limit_resources():
    for name, value in (('RLIMIT_CPU', 90), ('RLIMIT_FSIZE', 100 * 1024 * 1024), ('RLIMIT_NOFILE', 256)):
        limit = getattr(resource, name, None)
        if limit is not None:
            try:
                resource.setrlimit(limit, (value, value))
            except (ValueError, OSError):
                pass


def guard(allowed: list[Path]):
    """Schreiben nur in erlaubten Ordnern; kein Netzwerk."""
    original_open = builtins.open
    roots = [p.resolve() for p in allowed]

    def checked_open(file, mode='r', *args, **kwargs):
        if isinstance(file, (str, bytes, os.PathLike)) and any(flag in str(mode) for flag in 'wax+'):
            target = Path(os.fsdecode(file)).resolve()
            if not any(target == root or root in target.parents for root in roots):
                raise PermissionError(f'Schreiben außerhalb des erlaubten Ordners: {target}')
        return original_open(file, mode, *args, **kwargs)
    builtins.open = checked_open
    io.open = checked_open

    def no_network(*args, **kwargs):
        raise PermissionError('Netzwerk ist für Fähigkeiten gesperrt.')

    class BlockedSocket(socket.socket):
        """Bleibt eine Klasse (Bibliotheken leiten davon ab), verbindet aber nie."""
        connect = connect_ex = bind = sendto = no_network
    socket.socket = BlockedSocket       # type: ignore[misc]
    socket.create_connection = no_network
    socket.getaddrinfo = no_network


def main() -> int:
    mode, skill_dir, output_dir = sys.argv[1], Path(sys.argv[2]).resolve(), Path(sys.argv[3]).resolve()
    arguments = json.loads(sys.argv[4]) if len(sys.argv) > 4 else {}
    output_dir.mkdir(parents=True, exist_ok=True)
    limit_resources()
    # Eigener, leerer Temp-Ordner – nicht das ganze /tmp freigeben.
    private_tmp = Path(tempfile.mkdtemp(prefix='atlas-skill-tmp-'))
    os.environ['TMPDIR'] = str(private_tmp)
    tempfile.tempdir = str(private_tmp)
    guard([output_dir, private_tmp])
    sys.path.insert(0, str(skill_dir))
    os.chdir(output_dir)
    result: dict
    try:
        if mode == 'test':
            os.environ['ATLAS_SKILL_OUTPUT'] = str(output_dir)
            suite = unittest.defaultTestLoader.loadTestsFromName('test_skill')
            stream = io.StringIO()
            outcome = unittest.TextTestRunner(stream=stream, verbosity=2).run(suite)
            result = {'ok': outcome.wasSuccessful() and outcome.testsRun > 0, 'tests': outcome.testsRun,
                      'failures': len(outcome.failures) + len(outcome.errors), 'output': stream.getvalue()[-6000:]}
        else:
            import skill
            value = skill.run(arguments, str(output_dir))
            if not isinstance(value, dict):
                raise TypeError('run() muss ein dict zurückgeben.')
            result = {'ok': bool(value.get('ok', True)), 'result': value}
    except BaseException:  # noqa: BLE001 – jeder Fehler wird gemeldet, nicht verschluckt
        result = {'ok': False, 'error': traceback.format_exc()[-4000:]}
    sys.stdout.write(json.dumps(result, ensure_ascii=False, default=str) + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
