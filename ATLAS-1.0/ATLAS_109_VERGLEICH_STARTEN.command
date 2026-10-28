#!/bin/bash
cd "$(dirname "$0")" || exit 1
export PYTHONPATH="$PWD/Backend${PYTHONPATH:+:$PYTHONPATH}"
PY="$HOME/Library/Application Support/AtlasLocal/venv/bin/python3"
if [ ! -x "$PY" ]; then PY=python3; fi
"$PY" -m atlas.equivalence_suite --out "$PWD/ATLAS-VERGLEICH-ERGEBNISSE"
code=$?
echo ""
echo "Berichte: ATLAS-VERGLEICH-ERGEBNISSE/atlas_bericht.md"
echo "Beendet mit Status $code. Noch offene Praxisaufgaben sind normal."
read -r -p "Enter zum Schließen ..." _
