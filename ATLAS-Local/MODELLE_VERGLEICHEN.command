#!/bin/bash
# Optional: lädt passende lokale Sprachmodelle verschiedener Familien (Qwen, Llama, Mistral, Gemma …),
# vergleicht sie mit den 25 echten Arbeitsaufgaben und trägt das beste als Standard ein.
# Lädt nur nach Ihrer Zustimmung; nicht gewählte Modelle können Sie danach wieder löschen.
set -uo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export OLLAMA_HOST=127.0.0.1:11434
source Scripts/backend_common.sh
mkdir -p build
python_bin="$ATLAS_VENV/bin/python3"
[[ -x "$python_bin" ]] || python_bin=python3
command -v ollama >/dev/null || { echo 'Ollama fehlt – zuerst INSTALLIEREN.command.'; exit 1; }
ram=$(( $(sysctl -n hw.memsize) / 1073741824 ))
echo "Arbeitsspeicher: ${ram} GB. Vorgeschlagene Modelle (Download ca. GB, Werkzeuge, Hinweis):"
candidates=$(cd Backend && "$python_bin" -m atlas.models --ram "$ram")
echo "$candidates" | awk -F'\t' '{printf "  %-32s %5s GB  Werkzeuge: %-4s %s\n", $1, $2, $3, $4}'
free=$(df -g "$HOME" | awk 'NR==2 {print $4}')
echo "Freier Speicherplatz: ${free} GB."
read -r -p 'Fehlende Modelle jetzt laden und vergleichen? (j/n) ' answer
[[ "$answer" == j* || "$answer" == J* ]] || { echo 'Abgebrochen – nichts geladen.'; exit 0; }
loaded=()
while IFS=$'\t' read -r name size tools note; do
  if ollama list | awk 'NR>1 {print $1}' | grep -qx "$name"; then echo "vorhanden: $name"; continue; fi
  echo "Lade $name (ca. $size GB) …"
  ollama pull "$name" && loaded+=("$name")
done <<< "$candidates"
echo '== Vergleich mit den 25 Arbeitsaufgaben (dauert je Modell ca. 5–15 Minuten)'
(cd Backend && "$python_bin" -m atlas.realtests --compare --apply --output ../build/MAC-ECHTE-MODELLTESTS.json) || true
(cd Backend && "$python_bin" -m atlas.summary ../build)
if [[ ${#loaded[@]} -gt 0 ]]; then
  best=$("$python_bin" -c 'import json;print(json.load(open("build/MAC-ECHTE-MODELLTESTS.json")).get("best_model",""))' 2>/dev/null)
  echo "Gewählt: ${best:-?}"
  read -r -p 'Neu geladene, nicht gewählte Modelle wieder löschen, um Speicherplatz zu sparen? (j/n) ' answer
  if [[ "$answer" == j* || "$answer" == J* ]]; then
    for name in "${loaded[@]}"; do [[ "$name" == "$best" ]] || ollama rm "$name"; done
  fi
fi
