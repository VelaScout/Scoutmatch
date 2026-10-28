#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")" || exit 1
export PYTHONPATH="$PWD/Backend${PYTHONPATH:+:$PYTHONPATH}"
echo 'ATLAS – Intelligenztest (lokal, kostenlos, keine Downloads)'
echo 'Je nach Modell kann der Test mehrere Minuten dauern.'
if ! command -v python3 >/dev/null 2>&1; then
  echo 'Python 3 fehlt. Bitte zuerst INSTALLIEREN.command verwenden.'
  read -r -p 'Enter zum Schließen ...'
  exit 2
fi
python3 -m atlas.oneclick_intelligence --output "$HOME/Downloads/ATLAS-Testberichte"
status=$?
echo ''
echo 'Ergebnisordner: ~/Downloads/ATLAS-Testberichte'
read -r -p 'Enter zum Schließen ...'
exit "$status"
