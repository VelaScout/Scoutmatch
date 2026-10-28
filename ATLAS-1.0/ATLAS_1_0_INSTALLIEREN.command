#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo 'Nur Apple-Silicon-Mac unterstützt.'; exit 1; }
mkdir -p build
exec > >(tee build/ATLAS-1.0-INSTALLATION.log) 2>&1
printf '\nATLAS 1.0 – Build und Installation\n'
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; fi
xcodebuild -version
bash BAUEN.command
app="$PWD/build/DerivedData/Build/Products/Release/ATLAS.app"
[[ -d "$app" ]] || { echo 'Keine App erzeugt'; exit 1; }
mkdir -p "$HOME/Applications" "$HOME/Library/Application Support/Atlas1.0" "$HOME/Library/LaunchAgents"
target="$HOME/Applications/Atlas 1.0.app"
if [[ -d "$target" ]]; then
  backup="$HOME/Applications/Atlas 1.0 Backup $(date +%Y%m%d-%H%M%S).app"
  mv "$target" "$backup"
  echo "Vorherige App gesichert: $backup"
fi
/usr/bin/ditto "$app" "$target"
codesign --verify --strict "$target"
# Den VoiceServer an einen festen Ort kopieren; das Originalprojekt kann danach verschoben werden.
voice_home="$HOME/Library/Application Support/Atlas1.0/VoiceServer"
mkdir -p "$voice_home"
/usr/bin/ditto VoiceServer "$voice_home"
# XTTS als dauerhaften Benutzer-Dienst einrichten. Keine Systemrechte erforderlich.
if [[ -x "$HOME/.local/bin/uv" ]]; then
  voice_plist="$HOME/Library/LaunchAgents/de.atlas.local.xtts.plist"
  python3 - "$voice_plist" "$voice_home" "$HOME/.local/bin/uv" "$HOME/Library/Application Support/Atlas1.0/voice.log" <<'PYPLIST'
import plistlib,sys
from pathlib import Path
path,home,uv,log=map(Path,sys.argv[1:])
obj={'Label':'de.atlas.local.xtts','ProgramArguments':[str(uv),'run','--python','3.11','--with','coqui-tts[codec]','--with','torch','--with','torchaudio','python','atlas_voice_server.py'],'WorkingDirectory':str(home),'EnvironmentVariables':{'COQUI_TOS_AGREED':'1'},'RunAtLoad':True,'KeepAlive':{'SuccessfulExit':False},'StandardOutPath':str(log),'StandardErrorPath':str(log)}
path.write_bytes(plistlib.dumps(obj))
PYPLIST
  launchctl bootout "gui/$(id -u)" "$voice_plist" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$voice_plist" || echo 'WARNUNG: XTTS-Startdienst konnte nicht registriert werden.'
  launchctl kickstart -k "gui/$(id -u)/de.atlas.local.xtts" >/dev/null 2>&1 || true
  echo 'XTTS-Startdienst registriert. Erstes Laden kann einige Minuten dauern.'
else
  echo 'WARNUNG: uv nicht gefunden; XTTS kann nicht automatisch gestartet werden.'
fi
if curl --noproxy '*' -fsS --max-time 4 http://127.0.0.1:5002/health >/dev/null 2>&1; then
  echo 'XTTS: bereit'
else
  echo 'XTTS: noch nicht bereit. Prüfe ~/Library/Application Support/Atlas1.0/voice.log'
fi
# Die Spracheinstellung der App bleibt erhalten; Deutsch kann in Atlas-Einstellungen gewählt werden.
printf '\nINSTALLIERT: %s\n' "$target"
echo 'Alte Atlas-App beenden. Neue App wird geöffnet. Bitte nur diese neue App im Dock behalten.'
open "$target"
echo 'Fertig. Protokoll: build/ATLAS-1.0-INSTALLATION.log'
