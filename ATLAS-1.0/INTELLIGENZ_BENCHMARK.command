#!/bin/bash
cd "$(dirname "$0")" || exit 1
mkdir -p "$HOME/Downloads/ATLAS-Testberichte"
PYTHONPATH="$PWD/Backend" python3 -m atlas.intelligence_benchmark --output "$HOME/Downloads/ATLAS-Testberichte/intelligenz-vergleich.json"
status=$?
echo "Bericht: ~/Downloads/ATLAS-Testberichte/intelligenz-vergleich.json"
read -r -p 'Enter zum Schließen ...'
exit "$status"
