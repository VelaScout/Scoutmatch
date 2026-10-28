#!/bin/bash
cd "$(dirname "$0")" || exit 1
export PYTHONPATH="$PWD/Backend${PYTHONPATH:+:$PYTHONPATH}"
PY="$HOME/Library/Application Support/AtlasLocal/venv/bin/python3"
if [ ! -x "$PY" ]; then PY=python3; fi
"$PY" -m atlas.evidence_review --results ATLAS-VERGLEICH-ERGEBNISSE/atlas_ergebnisse.json --ledger ATLAS-VERGLEICH-ERGEBNISSE/manuelle_belege.json --out ATLAS-VERGLEICH-ERGEBNISSE/atlas_geprueft.json
code=$?
echo "Status: $code"
read -r -p "Enter zum Schließen ..." _
