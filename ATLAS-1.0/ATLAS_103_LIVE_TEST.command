#!/bin/bash
set -u
cd "$(dirname "$0")" || exit 1
PY="$HOME/Library/Application Support/AtlasLocal/venv/bin/python3"
if [ ! -x "$PY" ]; then PY="$(command -v python3)"; fi
mkdir -p Ergebnisse
PYTHONPATH="$PWD/Backend" "$PY" -m atlas.live_quality "$PWD/Ergebnisse"
RESULT=$?
echo ""
echo "Bericht: $PWD/Ergebnisse/ATLAS_103_QUALITAET.md"
echo "Test-Endcode: $RESULT"
read -r -p 'Enter zum Schliessen ... ' _
exit "$RESULT"
