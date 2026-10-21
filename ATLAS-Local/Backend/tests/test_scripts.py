"""Installations-, Update- und Rollback-Skripte – soweit ohne Mac prüfbar.

Echt ausgeführt (bash, in einem temporären HOME): Rollback-Skript mit Sicherungen, Autostart-
Datei aus backend_common.sh. Simuliert: launchctl (protokolliert nur). NICHT hier prüfbar:
xcodebuild, codesign, Homebrew, Ollama-Downloads – das prüfen die Skripte selbst auf dem Mac.
"""
import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]


class ScriptTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        self.log = self.home / 'launchctl.log'
        fake = self.bin / 'launchctl'
        fake.write_text(f'#!/bin/bash\necho "$@" >> "{self.log}"\n')
        fake.chmod(0o755)
        self.root = self.home / 'Library/Application Support/AtlasLocal'
        self.env = {**os.environ, 'HOME': str(self.home), 'PATH': f'{self.bin}:{os.environ["PATH"]}'}

    def run_script(self, *args, extra=None):
        return subprocess.run(['bash', *args], cwd=PROJECT, env={**self.env, **(extra or {})},
                              capture_output=True, text=True, timeout=60)

    def make_install(self, stamp='20261020-100000'):
        (self.root / 'Backend').mkdir(parents=True)
        (self.root / 'Backend' / 'version.txt').write_text('neu')
        (self.root / f'Backend-backup-{stamp}').mkdir()
        (self.root / f'Backend-backup-{stamp}' / 'version.txt').write_text('alt')
        apps = self.home / 'Applications'
        (apps / 'ATLAS Local.app').mkdir(parents=True)
        (apps / 'ATLAS Local.app' / 'v').write_text('neu')
        (apps / f'ATLAS Local-backup-{stamp}.app').mkdir()
        (apps / f'ATLAS Local-backup-{stamp}.app' / 'v').write_text('alt')
        agents = self.home / 'Library/LaunchAgents'
        agents.mkdir(parents=True)
        (agents / 'de.atlas.localbackend.plist').write_text('neu')
        (self.root / f'agent-backup-{stamp}.plist').write_text('alt')
        data = self.home / '.atlas-ai'
        data.mkdir()
        (data / 'atlas.db').write_text('neue gespräche')
        (self.root / f'Daten-backup-{stamp}').mkdir()
        (self.root / f'Daten-backup-{stamp}' / 'atlas.db').write_text('alte gespräche')

    def test_rollback_restores_app_backend_agent_and_keeps_data(self):
        self.make_install()
        done = self.run_script('ZURUECKSETZEN.command')
        self.assertEqual(done.returncode, 0, done.stderr + done.stdout)
        self.assertEqual((self.root / 'Backend' / 'version.txt').read_text(), 'alt')
        self.assertEqual((self.home / 'Applications/ATLAS Local.app/v').read_text(), 'alt')
        self.assertEqual((self.home / 'Library/LaunchAgents/de.atlas.localbackend.plist').read_text(), 'alt')
        # Nichts gelöscht: der neue Stand liegt daneben.
        self.assertEqual(len(list(self.root.glob('Backend-zurueckgesetzt-*'))), 1)
        self.assertEqual(len(list((self.home / 'Applications').glob('ATLAS Local-zurueckgesetzt-*.app'))), 1)
        # Gespräche bleiben ohne ausdrücklichen Wunsch unverändert.
        self.assertEqual((self.home / '.atlas-ai/atlas.db').read_text(), 'neue gespräche')
        log = self.log.read_text()
        self.assertIn('bootout', log)
        self.assertIn('bootstrap', log)

    def test_rollback_of_data_only_on_request_and_with_safety_copy(self):
        self.make_install()
        done = self.run_script('ZURUECKSETZEN.command', extra={'ATLAS_RESTORE_DATA': '1'})
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual((self.home / '.atlas-ai/atlas.db').read_text(), 'alte gespräche')
        safety = list(self.root.glob('Daten-vor-Zuruecksetzen-*/atlas.db'))
        self.assertEqual(safety[0].read_text(), 'neue gespräche')

    def test_rollback_without_backup_changes_nothing(self):
        (self.root / 'Backend').mkdir(parents=True)
        done = self.run_script('ZURUECKSETZEN.command')
        self.assertNotEqual(done.returncode, 0)
        self.assertIn('Keine Sicherung', done.stdout)
        self.assertTrue((self.root / 'Backend').is_dir())

    def test_autostart_file_uses_atlas_environment(self):
        venv = self.root / 'venv' / 'bin'
        venv.mkdir(parents=True)
        os.symlink(sys.executable, venv / 'python3')
        done = self.run_script('-c', 'set -euo pipefail; source Scripts/backend_common.sh; atlas_write_agent')
        self.assertEqual(done.returncode, 0, done.stderr)
        data = plistlib.loads((self.home / 'Library/LaunchAgents/de.atlas.localbackend.plist').read_bytes())
        self.assertEqual(data['ProgramArguments'], [str(venv / 'python3'), '-m', 'atlas.server'])
        self.assertEqual(data['WorkingDirectory'], str(self.root / 'Backend'))
        self.assertEqual(data['EnvironmentVariables']['ATLAS_PORT'], '8765')
        self.assertTrue(data['KeepAlive'])

    def test_all_scripts_have_valid_syntax_and_are_executable(self):
        scripts = list(PROJECT.glob('*.command')) + list((PROJECT / 'Scripts').glob('*.sh')) + list((PROJECT / 'Tests').glob('*.sh'))
        self.assertGreaterEqual(len(scripts), 7)
        for script in scripts:
            with self.subTest(script=script.name):
                self.assertEqual(subprocess.run(['bash', '-n', str(script)], capture_output=True).returncode, 0)
                if script.suffix == '.command':
                    self.assertTrue(os.access(script, os.X_OK))

    def test_update_never_replaces_before_build_and_tests(self):
        text = (PROJECT / 'AKTUALISIEREN.command').read_text()
        order = [text.index('bash BAUEN.command'), text.index('unittest discover'), text.index('mv "$ATLAS_INSTALL_ROOT/Backend"')]
        self.assertEqual(order, sorted(order))
        self.assertIn('Backend-backup-', text)
        self.assertIn('Daten-backup-', text)
        self.assertIn('agent-backup-', text)


if __name__ == '__main__':
    unittest.main()
