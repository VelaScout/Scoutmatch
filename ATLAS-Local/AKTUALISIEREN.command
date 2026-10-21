#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export OLLAMA_HOST=127.0.0.1:11434
[[ "$(uname -s)" == Darwin ]] || { echo 'Dieses Update benötigt macOS.'; exit 1; }
if pgrep -x ATLAS >/dev/null 2>&1; then echo 'Bitte Atlas zuerst über die Menüleiste beenden und Update erneut öffnen.'; exit 1; fi
source Scripts/backend_common.sh
[[ -d "$ATLAS_INSTALL_ROOT/Backend" && -f "$ATLAS_AGENT_PLIST" ]] || { echo 'Vorherige Installation fehlt. Bitte INSTALLIEREN.command verwenden.'; exit 1; }
# 1. Erst alles bauen und prüfen – vorher wird nichts ersetzt.
bash BAUEN.command
atlas_setup_venv
(cd Backend && "$ATLAS_VENV/bin/python3" -W error::ResourceWarning -m unittest discover -s tests -v)
atlas_pull_models
# 2. Sicherungen anlegen, dann austauschen (Rückkehr: Backup-Ordner zurückbenennen).
stamp=$(date +%Y%m%d-%H%M%S)
ditto Backend "$ATLAS_INSTALL_ROOT/Backend-staging-$stamp"
destination="$HOME/Applications/ATLAS Local.app"
new_app="$HOME/Applications/ATLAS Local-staging-$stamp.app"
ditto build/DerivedData/Build/Products/Release/ATLAS.app "$new_app"
codesign --verify --strict "$new_app"
launchctl bootout "gui/$(id -u)/$ATLAS_LABEL" >/dev/null 2>&1 || true
if [[ -f "$HOME/.atlas-ai/atlas.db" ]]; then
  mkdir -p "$ATLAS_INSTALL_ROOT/Daten-backup-$stamp" && cp -p "$HOME/.atlas-ai/atlas.db" "$ATLAS_INSTALL_ROOT/Daten-backup-$stamp/"
fi
mv "$ATLAS_INSTALL_ROOT/Backend" "$ATLAS_INSTALL_ROOT/Backend-backup-$stamp"
mv "$ATLAS_INSTALL_ROOT/Backend-staging-$stamp" "$ATLAS_INSTALL_ROOT/Backend"
if [[ -d "$destination" ]]; then mv "$destination" "$HOME/Applications/ATLAS Local-backup-$stamp.app"; fi
mv "$new_app" "$destination"
cp "$ATLAS_AGENT_PLIST" "$ATLAS_INSTALL_ROOT/agent-backup-$stamp.plist"
atlas_write_agent
launchctl bootstrap "gui/$(id -u)" "$ATLAS_AGENT_PLIST"
atlas_verify_service
open "$destination"
echo "Atlas 0.5.0 aktualisiert. Gesprächsdaten, Gedächtnis und Modelle bleiben erhalten."
echo "Sicherungen: $ATLAS_INSTALL_ROOT (Backend-backup-$stamp, Daten-backup-$stamp) und ~/Applications/ATLAS Local-backup-$stamp.app"
echo 'Kurztest mit dem echten Modell (3 Aufgaben) …'
mkdir -p build
(cd Backend && "$ATLAS_VENV/bin/python3" -m atlas.realtests --quick --output ../build/MAC-ECHTE-MODELLTESTS.json) || true
(cd Backend && "$ATLAS_VENV/bin/python3" -m atlas.summary ../build) || true
echo 'Ausführlich (12 Aufgaben, ca. 5–10 Minuten): MAC_TESTEN.command'
