"""Regression: Modellvergleich mit nur einem Kandidaten muss die Empfehlung übernehmen."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from atlas import realtests as r

class ModelSelectionTests(unittest.TestCase):
    def test_single_candidate_is_scored_and_applied(self):
        with tempfile.TemporaryDirectory() as tmp:
            report = Path(tmp) / 'result.json'
            model = r.CANDIDATES[0]
            with patch('sys.argv', ['realtests', '--compare', '--apply', '--output', str(report)]), \
                 patch('atlas.realtests.llm.Ollama') as client_class, \
                 patch('atlas.realtests.run_suite', return_value=[{'passed': True, 'status': 'BESTANDEN', 'total_s': 1}]), \
                 patch('atlas.realtests.apply_recommendation', return_value=Path(tmp) / 'settings.json') as apply:
                client = client_class.return_value
                client.installed.return_value = [model]
                client.fast_model.return_value = model
                client.agent_model.return_value = model
                client.reasoning_only.return_value = False
                self.assertEqual(r.main(), 0)
                self.assertEqual(json.loads(report.read_text())['best_model'], model)
                apply.assert_called_once_with(model)
