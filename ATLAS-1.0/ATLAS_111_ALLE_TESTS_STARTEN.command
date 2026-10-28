#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export PYTHONPATH="$PWD/Backend${PYTHONPATH:+:$PYTHONPATH}"
PY="$HOME/Library/Application Support/AtlasLocal/venv/bin/python3"
if [ ! -x "$PY" ]; then PY="$(command -v python3 || true)"; fi
if [ -z "$PY" ]; then echo 'Python 3 fehlt. Bitte ATLAS zuerst installieren.'; read -r -p 'Enter zum Schließen ...' _; exit 2; fi
OUT="$HOME/Downloads/ATLAS-GESAMTTEST-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
echo 'ATLAS 1.0.11: Vollständiger Selbsttest'
echo 'Ollama und ATLAS sollten vor dem Start laufen. Kein Cloud-Upload.'
echo "Ergebnisse: $OUT"
"$PY" -m atlas.full_mac_audit --out "$OUT"
RESULT=$?
if command -v open >/dev/null 2>&1; then open "$OUT/GESAMTBERICHT.md" 2>/dev/null || true; fi
echo 'Fertig. Offene manuelle Tests sind kein Bestehen.'
read -r -p 'Enter zum Schließen ...' _
exit "$RESULT"
