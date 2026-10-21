#!/bin/bash
# Stellt den Stand vor dem letzten Update wieder her (App, Backend, Autostart).
# Gesprächsdaten und Erinnerungen bleiben unverändert – sie werden nur mit
# ATLAS_RESTORE_DATA=1 auf die Sicherung zurückgesetzt (dann gehen neuere Gespräche verloren;
# der aktuelle Stand wird vorher zusätzlich gesichert).
set -euo pipefail
cd "$(dirname "$0")"
source Scripts/backend_common.sh
if command -v pgrep >/dev/null && pgrep -x ATLAS >/dev/null 2>&1; then
  echo 'Bitte Atlas zuerst über die Menüleiste beenden.'; exit 1
fi
latest() { { ls -1d "$@" 2>/dev/null || true; } | sort | tail -1; }
backend=$(latest "$ATLAS_INSTALL_ROOT"/Backend-backup-*)
[[ -n "$backend" ]] || { echo 'Keine Sicherung gefunden – es gibt nichts zurückzusetzen.'; exit 1; }
stamp=${backend##*Backend-backup-}
now=$(date +%Y%m%d-%H%M%S)
echo "Setze zurück auf den Stand vor dem Update vom $stamp …"
if command -v launchctl >/dev/null; then launchctl bootout "gui/$(id -u)/$ATLAS_LABEL" >/dev/null 2>&1 || true; fi
# Aktuellen Stand nicht löschen, sondern beiseitelegen (Rückweg bleibt möglich).
[[ -d "$ATLAS_INSTALL_ROOT/Backend" ]] && mv "$ATLAS_INSTALL_ROOT/Backend" "$ATLAS_INSTALL_ROOT/Backend-zurueckgesetzt-$now"
mv "$backend" "$ATLAS_INSTALL_ROOT/Backend"
app_backup="$HOME/Applications/ATLAS Local-backup-$stamp.app"
if [[ -d "$app_backup" ]]; then
  [[ -d "$HOME/Applications/ATLAS Local.app" ]] && mv "$HOME/Applications/ATLAS Local.app" "$HOME/Applications/ATLAS Local-zurueckgesetzt-$now.app"
  mv "$app_backup" "$HOME/Applications/ATLAS Local.app"
fi
if [[ -f "$ATLAS_INSTALL_ROOT/agent-backup-$stamp.plist" ]]; then
  cp "$ATLAS_AGENT_PLIST" "$ATLAS_INSTALL_ROOT/agent-zurueckgesetzt-$now.plist" 2>/dev/null || true
  cp "$ATLAS_INSTALL_ROOT/agent-backup-$stamp.plist" "$ATLAS_AGENT_PLIST"
fi
if [[ "${ATLAS_RESTORE_DATA:-0}" == 1 && -f "$ATLAS_INSTALL_ROOT/Daten-backup-$stamp/atlas.db" ]]; then
  mkdir -p "$ATLAS_INSTALL_ROOT/Daten-vor-Zuruecksetzen-$now"
  [[ -f "$HOME/.atlas-ai/atlas.db" ]] && cp -p "$HOME/.atlas-ai/atlas.db" "$ATLAS_INSTALL_ROOT/Daten-vor-Zuruecksetzen-$now/"
  cp -p "$ATLAS_INSTALL_ROOT/Daten-backup-$stamp/atlas.db" "$HOME/.atlas-ai/atlas.db"
  echo 'Backend-Datenbank auf die Sicherung zurückgesetzt (aktueller Stand gesichert).'
fi
if command -v launchctl >/dev/null; then launchctl bootstrap "gui/$(id -u)" "$ATLAS_AGENT_PLIST"; fi
echo "Zurückgesetzt. Der vorherige Stand liegt unter *-zurueckgesetzt-$now (zum erneuten Wechseln)."
