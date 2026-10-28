"""Betriebssystem-Sandbox: Selbstprüfung und Verhalten bei defekter Sandbox.

Auf Linux: mit nachgebauten, absichtlich fehlerhaften sandbox-exec-Programmen (echt ausgeführt).
Auf dem Mac: zusätzlich mit dem echten sandbox-exec (MacSandboxTests; hier NICHT AUSGEFÜHRT).
"""
import os
import platform
import shutil
import stat
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from atlas import sandbox
from atlas.skills import run_harness

REAL = platform.system() == 'Darwin' and shutil.which('sandbox-exec') and not os.environ.get('ATLAS_IN_SANDBOX')


class FakeSandboxTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        sandbox.reset()
        self.addCleanup(sandbox.reset)

    def fake(self, script):
        path = self.bin / 'sandbox-exec'
        path.write_text('#!/bin/sh\n' + script)
        path.chmod(path.stat().st_mode | stat.S_IEXEC)
        patcher = mock.patch.dict(os.environ, {'PATH': f'{self.bin}:{os.environ["PATH"]}'})
        patcher.start()
        self.addCleanup(patcher.stop)

    def skill(self):
        folder = self.root / 'skill'
        folder.mkdir()
        marker = self.root / 'lief.txt'
        (folder / 'skill.py').write_text(f'def run(args, output_dir):\n    open({str(marker)!r}, "w").write("x")\n    return {{"ok": True}}\n')
        return folder, marker

    def test_sandbox_that_does_not_protect_is_never_used(self):
        self.fake('shift 2\nexec "$@"\n')                     # führt aus, schützt aber nicht
        with self.assertRaises(sandbox.SandboxError) as caught:
            sandbox.wrap(['true'], [self.root], 'none')
        self.assertIn('außerhalb NICHT', str(caught.exception))
        folder, marker = self.skill()
        result = run_harness('run', folder, self.root / 'out')
        self.assertFalse(result['ok'])
        self.assertIn('macOS-Sandbox', result['error'])
        self.assertFalse(marker.exists())                         # Fähigkeit lief gar nicht erst

    def test_rejected_profile_gives_clear_message(self):
        self.fake('echo "sandbox-exec: syntax error" >&2\nexit 65\n')
        status = sandbox.status()
        self.assertTrue(status['available'])
        self.assertIn('nicht angenommen', status['none'])
        self.assertIn('syntax error', status['localhost'])

    def test_nested_sandbox_is_not_attempted(self):
        self.fake('exit 1\n')
        with mock.patch.dict(os.environ, {'ATLAS_IN_SANDBOX': '1'}):
            self.assertFalse(sandbox.available())


@unittest.skipUnless(REAL, 'nur auf dem Mac mit echtem sandbox-exec')
class MacSandboxTests(unittest.TestCase):
    """Läuft automatisch im Update und in MAC_TESTEN.command auf dem Mac."""

    def setUp(self):
        sandbox.reset()

    def test_profiles_work_for_skills_and_workshop(self):
        status = sandbox.status()
        self.assertTrue(status['none'].startswith('Variante'), status)
        self.assertTrue(status['localhost'].startswith('Variante'), status)

    def test_skill_cannot_write_outside_but_can_use_temp(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve()
            folder = root / 'skill'
            folder.mkdir()
            outside = Path.home() / f'.atlas-sandbox-probe-{os.getpid()}'
            (folder / 'skill.py').write_text(
                'import tempfile\ndef run(args, output_dir):\n'
                '    with tempfile.NamedTemporaryFile() as f: f.write(b"ok")\n'
                f'    try:\n        open({str(outside)!r}, "w").write("x")\n    except OSError:\n        pass\n'
                '    return {"ok": True}\n')
            result = run_harness('run', folder, root / 'out')
            self.assertTrue(result['ok'], result)
            self.assertFalse(outside.exists())


if __name__ == '__main__':
    unittest.main()
