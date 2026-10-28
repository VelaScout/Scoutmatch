#!/bin/bash
# ATLAS-Optimierung: passende Modelle für diesen Mac laden, auf Ihrem Mac messen, das beste einstellen.
cd "$(dirname "$0")" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
HERE="$PWD"
PRUEF=""
for candidate in "$HERE/ATLAS-1.0-GESAMTPRUEFUNG" "$HOME/Downloads/ATLAS-1.0-GESAMTPRUEFUNG"; do
  [ -f "$candidate/atlas_optimierung.py" ] && { PRUEF="$candidate"; break; }
done
if [ -z "$PRUEF" ] || [ ! -d "$HERE/Backend/atlas" ]; then
  echo 'Bitte diese Datei im ATLAS-Ordner starten (dort, wo „Backend“ und „ATLAS-1.0-GESAMTPRUEFUNG“ liegen).'
  read -r -p 'Enter zum Schließen …' _; exit 2
fi
PY="$HOME/Library/Application Support/AtlasLocal/venv/bin/python3"
[ -x "$PY" ] || PY="$(command -v python3)"
export PYTHONPATH="$HERE/Backend:$PRUEF"
echo '=== ATLAS-Optimierung für diesen Mac ==='
if ! curl -s -m 3 http://127.0.0.1:11434/api/tags >/dev/null; then
  echo 'Ollama läuft nicht. Bitte die Ollama-App starten und Enter drücken.'; read -r -p '' _
fi
if ! curl -s -m 3 http://127.0.0.1:8765/api/health >/dev/null; then
  echo 'Der ATLAS-Dienst antwortet nicht. Bitte die ATLAS-App starten und Enter drücken.'; read -r -p '' _
fi
ARGS=(--backend "$HERE/Backend")
echo
echo 'Für einen Mac mit 16 GB empfohlen (kostenlos, nur Speicherplatz):'
echo '  qwen3:8b   ca. 5 GB  – stärkeres Denkmodell'
echo '  qwen3:14b  ca. 9 GB  – noch stärker, auf 16 GB aber langsam (wird gemessen und nur genommen, wenn es flüssig läuft)'
echo '  gemma3:4b  ca. 3 GB  – Bilder und Fotos verstehen'
read -r -p 'Fehlende Modelle jetzt herunterladen? [J/n] ' LADEN
case "$LADEN" in n|N|nein|Nein) ;; *) ARGS+=(--laden);; esac
read -r -p 'Auch das Arbeitsmodell neu wählen? Dauert ca. 1 Stunde. [j/N] ' ARBEIT
case "$ARBEIT" in j|J|ja|Ja) ARGS+=(--arbeitsmodell);; esac
echo
echo 'Die Messung dauert je Modell etwa 5–30 Minuten. Bitte währenddessen nichts Großes am Mac starten.'
cd "$PRUEF" && "$PY" atlas_optimierung.py "${ARGS[@]}"
[ -f "$HOME/Downloads/ATLAS-OPTIMIERUNG/OPTIMIERUNG.md" ] && open "$HOME/Downloads/ATLAS-OPTIMIERUNG/OPTIMIERUNG.md"
read -r -p 'Fertig. Enter zum Schließen …' _
