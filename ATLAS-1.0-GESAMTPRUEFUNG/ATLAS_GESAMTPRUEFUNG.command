#!/bin/bash
# ATLAS-Gesamtprüfung – diesen Ordner in den ATLAS-Ordner legen (neben „Backend“) und doppelklicken.
cd "$(dirname "$0")" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
# ATLAS-Ordner finden: zuerst eine Ebene höher, sonst die neueste Atlas-1.0-Version in Downloads oder Schreibtisch.
ATLAS_DIR="$(cd .. && pwd)"
if [ ! -d "$ATLAS_DIR/Backend/atlas" ]; then
  ATLAS_DIR=""
  FOUND="$(ls -dt "$HOME"/Downloads/*/Backend/atlas/full_mac_audit.py "$HOME"/Desktop/*/Backend/atlas/full_mac_audit.py 2>/dev/null | head -1)"
  [ -n "$FOUND" ] && ATLAS_DIR="$(cd "$(dirname "$FOUND")/../.." && pwd)"
fi
if [ -z "$ATLAS_DIR" ]; then
  echo "Keinen ATLAS-1.0-Ordner gefunden. Bitte den Ordner „ATLAS-1.0-GESAMTPRUEFUNG“ in den ATLAS-Ordner legen (neben „Backend“)."
  read -r -p 'Enter zum Schließen …' _; exit 2
fi
echo "Geprüft wird: $ATLAS_DIR"
PY="$HOME/Library/Application Support/AtlasLocal/venv/bin/python3"
[ -x "$PY" ] || PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo 'Python 3 fehlt. Bitte ATLAS zuerst installieren.'; read -r -p 'Enter …' _; exit 2; fi
export PYTHONPATH="$ATLAS_DIR/Backend:$PWD"
OUT="$HOME/Downloads/ATLAS-GESAMTPRUEFUNG"

echo '=== ATLAS-Gesamtprüfung ==='
echo "Ergebnisse: $OUT"
if ! curl -s -m 3 http://127.0.0.1:8765/api/health >/dev/null; then
  echo 'Der ATLAS-Dienst antwortet nicht. Bitte die ATLAS-App und Ollama starten und dann Enter drücken.'
  read -r -p 'Enter, wenn ATLAS läuft …' _
fi

ARGS=(--out "$OUT" --backend "$ATLAS_DIR/Backend")
if [ -f "$OUT/fortschritt.jsonl" ]; then
  read -r -p 'Es gibt einen unterbrochenen Lauf. Fortsetzen? [J/n] ' WEITER
  case "$WEITER" in n|N|nein|Nein) ARGS+=(--neu);; esac
fi

echo
echo 'Optional: Vergleich mit Claude (dieselben Fragen, offizielle Anthropic-API).'
echo '- Den Mac verlassen NUR die Testfragen dieses Katalogs – keine Dateien, kein Gedächtnis, keine Gespräche.'
echo '- Kosten: höchstens 2 US-$ (danach wird automatisch aufgehört). Der Schlüssel kommt aus dem Schlüsselbund.'
read -r -p 'Claude-Vergleich durchführen? [j/N] ' CLAUDE
case "$CLAUDE" in j|J|ja|Ja) ARGS+=(--vergleich-claude);; esac

echo
echo 'Die Prüfung dauert etwa 20–40 Minuten. Abbrechen ist jederzeit möglich (Ctrl+C) –'
echo 'beim nächsten Start geht es an derselben Stelle weiter.'
"$PY" atlas_gesamtpruefung.py "${ARGS[@]}"
RESULT=$?
[ -f "$OUT/GESAMTBERICHT.md" ] && open "$OUT/GESAMTBERICHT.md" 2>/dev/null
read -r -p 'Fertig. Enter zum Schließen …' _
exit $RESULT
