#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")" || exit 1
export PYTHONPATH="$PWD/Backend${PYTHONPATH:+:$PYTHONPATH}"
mkdir -p "$HOME/Downloads/ATLAS-Testberichte"
python3 -m atlas.intelligence_ab --model "${ATLAS_MODEL:-qwen3:8b}" --output "$HOME/Downloads/ATLAS-Testberichte/intelligenz-ab.json"
status=$?
echo "Bericht: $HOME/Downloads/ATLAS-Testberichte/intelligenz-ab.json"
read -r -p "Enter zum Schließen ..."
exit "$status"
