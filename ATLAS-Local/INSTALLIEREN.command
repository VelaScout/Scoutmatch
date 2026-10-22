#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export OLLAMA_HOST=127.0.0.1:11434
trap 'code=$?; if [[ $code != 0 ]]; then echo "Installation gestoppt. Bitte die letzte Fehlermeldung und build/BUILD-LOG.txt prüfen."; fi' EXIT
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo 'Für MacBook mit Apple Silicon vorgesehen.'; exit 1; }
if pgrep -x ATLAS >/dev/null 2>&1; then
  echo 'Bitte zuerst die laufende Atlas-App über die Menüleiste beenden und diesen Starter erneut öffnen.'
  exit 1
fi
command -v brew >/dev/null || { echo 'Homebrew fehlt. Bitte nach Anleitung auf https://brew.sh installieren und erneut starten.'; exit 1; }
for formula in python ollama ffmpeg whisper-cpp; do
  brew list --formula "$formula" >/dev/null 2>&1 || brew install "$formula"
done
python3 -c 'import sys; assert sys.version_info >= (3,10), "Python 3.10 oder neuer erforderlich"'
source Scripts/backend_common.sh
# Kompilieren und prüfen, bevor die installierte App oder der Dienst verändert wird.
bash BAUEN.command
atlas_setup_venv
(cd Backend && "$ATLAS_VENV/bin/python3" -W error::ResourceWarning -m unittest discover -s tests -v)
if ! curl --noproxy '*' -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  brew services start ollama
fi
ready=0
for i in {1..30}; do
  if curl --noproxy '*' -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
[[ "$ready" == 1 ]] || { echo 'Ollama ist nicht erreichbar. Bitte Ollama öffnen und erneut starten.'; exit 1; }
atlas_pull_models
# Whisper wird von der Weboberfläche/Diagnose genutzt; die App erkennt Sprache mit Apple auf dem Gerät.
mkdir -p "$HOME/.atlas-ai/models"
if [[ ! -s "$HOME/.atlas-ai/models/ggml-base.bin" ]]; then
  curl --fail --location --retry 3 https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin -o "$HOME/.atlas-ai/models/ggml-base.bin.partial"
  mv "$HOME/.atlas-ai/models/ggml-base.bin.partial" "$HOME/.atlas-ai/models/ggml-base.bin"
fi
# Nur den eigenen, früher installierten Dienst stoppen; nie einen fremden Prozess am Port beenden.
launchctl bootout "gui/$(id -u)/$ATLAS_LABEL" >/dev/null 2>&1 || true
"$ATLAS_VENV/bin/python3" - <<'PY'
import socket
with socket.socket() as s:
    if s.connect_ex(('127.0.0.1',8765)) == 0:
        raise SystemExit('Port 8765 ist belegt. Bitte den früheren Atlas-Terminalstarter mit Ctrl+C beenden und Installation wiederholen.')
PY
mkdir -p "$HOME/Applications"
stamp=$(date +%Y%m%d-%H%M%S)
# Sicherung vor dem Ersetzen; die ursprüngliche ATLAS.app bleibt unangetastet.
if [[ -d "$ATLAS_INSTALL_ROOT/Backend" ]]; then mv "$ATLAS_INSTALL_ROOT/Backend" "$ATLAS_INSTALL_ROOT/Backend-backup-$stamp"; fi
ditto Backend "$ATLAS_INSTALL_ROOT/Backend"
destination="$HOME/Applications/ATLAS Local.app"
if [[ -d "$destination" ]]; then mv "$destination" "$HOME/Applications/ATLAS Local-backup-$stamp.app"; fi
ditto build/DerivedData/Build/Products/Release/ATLAS.app "$destination"
# Gleiche Bundle-ID und Sandbox erhalten die vorhandenen SwiftData-Daten. Zusätzlich eine Sicherung.
old_store="$HOME/Library/Containers/de.atlas.assistant.BITTE-AENDERN/Data/Library/Application Support"
if [[ -d "$old_store" ]]; then
  ditto "$old_store" "$ATLAS_INSTALL_ROOT/NativeData-backup-$stamp" || { echo 'Datensicherung fehlgeschlagen; App wurde noch nicht geöffnet.'; exit 1; }
fi
atlas_write_agent
launchctl bootstrap "gui/$(id -u)" "$ATLAS_AGENT_PLIST"
atlas_verify_service
open "$destination"
echo 'Installiert: ~/Applications/ATLAS Local.app (Version 0.8.1)'
echo 'Der lokale Backend-Dienst startet künftig bei Ihrer Anmeldung. DEINSTALLIEREN.command entfernt diesen Dienst, ohne Gesprächsdaten zu löschen.'
echo 'Beim ersten Datei- oder Ordnerzugriff fragt macOS, ob „python3“ zugreifen darf – das ist der Atlas-Dienst.'
echo 'Empfohlen: MAC_TESTEN.command prüft jetzt die echten Modellfähigkeiten.'
