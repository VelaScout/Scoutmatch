#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")" || exit 1
export PYTHONPATH="$PWD/Backend${PYTHONPATH:+:$PYTHONPATH}"
mkdir -p "$HOME/Downloads/ATLAS-Testberichte"
python3 -m atlas.realtests --compare --apply --output "$HOME/Downloads/ATLAS-Testberichte/intelligenz-vergleich.json"
result=$?
echo "Bericht: ~/Downloads/ATLAS-Testberichte/intelligenz-vergleich.json"
read -r -p "Enter zum Schließen ..."
exit "$result"
