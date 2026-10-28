#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
PYTHON="${HOME}/Library/Application Support/AtlasLocal/venv/bin/python3"
if [ ! -x "$PYTHON" ]; then PYTHON="$(command -v python3)"; fi
"$PYTHON" -m unittest discover -s "$ROOT/Backend/tests" -p test_quality_checks.py -v
printf '\nQualitaetspruefungen beendet. Zum Schliessen Enter druecken.\n'
read -r _
