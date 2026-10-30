#!/bin/bash
# ATLAS Core 2.0.3 – Update nur des lokalen ATLAS-Dienstes (Backend). Die App bleibt unverändert.
# Neu: Sicherheitsschutz, Formatwächter, Denkmodus für Rechnen/Logik, Pfad-Korrektur, Suche mit mehreren Diensten.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
mkdir -p build
exec > >(tee build/UPDATE.txt) 2>&1
trap 'code=$?; if [[ $code -ne 0 ]]; then echo; echo "Update abgebrochen (Fehler $code). Es wurde nichts ersetzt, bzw. der alte Stand wurde wiederhergestellt."; echo "Protokoll: $PWD/build/UPDATE.txt"; read -r -p "Enter zum Schließen …" _; fi' EXIT
[[ "$(uname -s)" == Darwin ]] || { echo 'Dieses Update benötigt macOS.'; exit 1; }
if pgrep -x ATLAS >/dev/null 2>&1; then
  echo 'Bitte die ATLAS-App zuerst beenden (Menüleiste → Beenden) und das Update erneut öffnen.'; exit 1
fi
source Scripts/backend_common.sh
[[ -d "$ATLAS_INSTALL_ROOT/Backend" && -f "$ATLAS_AGENT_PLIST" ]] || { echo 'Keine ATLAS-Installation gefunden. Bitte zuerst installieren.'; exit 1; }

echo '== 1. Python-Umgebung prüfen (neu: certifi für die Internetsuche)'
atlas_setup_venv
echo '== 2. Tests des neuen Stands – nur wenn alle bestehen, wird etwas ersetzt'
(cd Backend && "$ATLAS_VENV/bin/python3" -W error::ResourceWarning -m unittest discover -s tests)

echo '== 3. Sicherung und Austausch'
stamp=$(date +%Y%m%d-%H%M%S)
ditto Backend "$ATLAS_INSTALL_ROOT/Backend-staging-$stamp"
if [[ -f "$HOME/.atlas-ai/atlas.db" ]]; then
  mkdir -p "$ATLAS_INSTALL_ROOT/Daten-backup-$stamp" && cp -p "$HOME/.atlas-ai/atlas.db" "$ATLAS_INSTALL_ROOT/Daten-backup-$stamp/"
fi
launchctl bootout "gui/$(id -u)/$ATLAS_LABEL" >/dev/null 2>&1 || true
mv "$ATLAS_INSTALL_ROOT/Backend" "$ATLAS_INSTALL_ROOT/Backend-backup-$stamp"
mv "$ATLAS_INSTALL_ROOT/Backend-staging-$stamp" "$ATLAS_INSTALL_ROOT/Backend"
launchctl bootstrap "gui/$(id -u)" "$ATLAS_AGENT_PLIST"
if ! atlas_verify_service; then
  echo 'Der neue Dienst startet nicht – stelle den alten Stand wieder her.'
  launchctl bootout "gui/$(id -u)/$ATLAS_LABEL" >/dev/null 2>&1 || true
  mv "$ATLAS_INSTALL_ROOT/Backend" "$ATLAS_INSTALL_ROOT/Backend-fehlgeschlagen-$stamp"
  mv "$ATLAS_INSTALL_ROOT/Backend-backup-$stamp" "$ATLAS_INSTALL_ROOT/Backend"
  launchctl bootstrap "gui/$(id -u)" "$ATLAS_AGENT_PLIST"
  exit 1
fi
echo
echo 'ATLAS Core 2.0.3 ist aktiv. Gespräche, Gedächtnis und Modelle bleiben erhalten.'
echo "Sicherung des alten Stands: $ATLAS_INSTALL_ROOT/Backend-backup-$stamp"
echo 'Jetzt die ATLAS-App wieder starten, dann ATLAS_OPTIMIEREN.command und danach die Gesamtprüfung.'
trap - EXIT
read -r -p 'Fertig. Enter zum Schließen …' _
