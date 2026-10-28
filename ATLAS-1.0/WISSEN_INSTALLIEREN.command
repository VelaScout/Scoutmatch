#!/bin/bash
# ATLAS Wissenspakete: ein Doppelklick, ohne Terminal-Pfadkenntnisse.
set -e
cd "$(dirname "$0")"
ROOT="$(pwd)"
echo "ATLAS Wissenspakete – lokale Installation"
echo "Projekt: $ROOT"
if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 fehlt. Bitte Xcode Command Line Tools installieren."
  read -r -p "Enter zum Beenden ..." _
  exit 1
fi
if [ ! -f Backend/tools/wissenspakete.py ]; then
  echo "Fehler: Lernskript im Projektordner nicht gefunden."
  read -r -p "Enter zum Beenden ..." _
  exit 1
fi
DATA_DIR="${ATLAS_DATA_DIR:-$HOME/.atlas-ai}"
DB="$DATA_DIR/atlas.db"
mkdir -p "$DATA_DIR"
if [ -f "$DB" ]; then
  BACKUP="$DB.backup-wissenspakete-$(date +%Y%m%d-%H%M%S)"
  python3 - "$DB" "$BACKUP" <<'PYBACKUP'
import sqlite3,sys
with sqlite3.connect(sys.argv[1]) as source, sqlite3.connect(sys.argv[2]) as dest:
    source.backup(dest)
print('Datenbanksicherung erstellt:', sys.argv[2])
PYBACKUP
fi
python3 Backend/tools/wissenspakete.py --datenbank "$DB" --pakete alle --einreihen
python3 Backend/tools/wissen_test.py --datenbank "$DB"
echo "Fertig. Öffne ATLAS und aktiviere die Lernverarbeitung in Learning & Evolution."
echo "Internetrecherche startet nicht durch die Installation selbst."
read -r -p "Enter zum Schließen ..." _
