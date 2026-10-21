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
# Compile and validate before changing the installed app or service.
bash BAUEN.command
command -v brew >/dev/null || { echo 'Homebrew fehlt. Bitte nach Anleitung auf https://brew.sh installieren und erneut starten.'; exit 1; }
for formula in python ollama ffmpeg whisper-cpp; do
  brew list --formula "$formula" >/dev/null 2>&1 || brew install "$formula"
done
python3 -c 'import sys; assert sys.version_info >= (3,10), "Python 3.10 oder neuer erforderlich"'
(cd Backend && python3 -W error::ResourceWarning -m unittest discover -s tests -v)
if ! curl --noproxy '*' -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  brew services start ollama
fi
ready=0
for i in {1..30}; do
  if curl --noproxy '*' -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
[[ "$ready" == 1 ]] || { echo 'Ollama ist nicht erreichbar. Bitte Ollama öffnen und erneut starten.'; exit 1; }
ollama pull qwen3:4b
# Whisper is used by the included web client/diagnostics; native speech uses Apple on-device.
mkdir -p "$HOME/.atlas-ai/models"
if [[ ! -s "$HOME/.atlas-ai/models/ggml-base.bin" ]]; then
  curl --fail --location --retry 3 https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin -o "$HOME/.atlas-ai/models/ggml-base.bin.partial"
  mv "$HOME/.atlas-ai/models/ggml-base.bin.partial" "$HOME/.atlas-ai/models/ggml-base.bin"
fi
label=de.atlas.localbackend
agent="$HOME/Library/LaunchAgents/$label.plist"
# Only stop our own previously installed service; never kill a process by its port.
launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
python3 - <<'PY'
import socket
with socket.socket() as s:
    if s.connect_ex(('127.0.0.1',8765)) == 0:
        raise SystemExit('Port 8765 ist belegt. Bitte den früheren Atlas-Terminalstarter mit Ctrl+C beenden und Installation wiederholen.')
PY
install_root="$HOME/Library/Application Support/AtlasLocal"
mkdir -p "$install_root" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/AtlasLocal" "$HOME/Applications"
stamp=$(date +%Y%m%d-%H%M%S)
# Backup before replacing an existing local build; the original ATLAS.app is left in place.
if [[ -d "$install_root/Backend" ]]; then mv "$install_root/Backend" "$install_root/Backend-backup-$stamp"; fi
ditto Backend "$install_root/Backend"
destination="$HOME/Applications/ATLAS Local.app"
if [[ -d "$destination" ]]; then mv "$destination" "$HOME/Applications/ATLAS Local-backup-$stamp.app"; fi
ditto build/DerivedData/Build/Products/Release/ATLAS.app "$destination"
# Same bundle identifier and sandbox preserve the existing SwiftData store. Copy a backup if accessible.
old_store="$HOME/Library/Containers/de.atlas.assistant.BITTE-AENDERN/Data/Library/Application Support"
if [[ -d "$old_store" ]]; then
  ditto "$old_store" "$install_root/NativeData-backup-$stamp" || { echo 'Datensicherung fehlgeschlagen; App wurde noch nicht geöffnet.'; exit 1; }
fi
export ATLAS_INSTALL_ROOT="$install_root" ATLAS_AGENT_PATH="$agent"
python3 - <<'PY'
import os, pathlib, plistlib, sys
root=pathlib.Path(os.environ['ATLAS_INSTALL_ROOT'])
logs=pathlib.Path.home()/'Library/Logs/AtlasLocal'
data={'Label':'de.atlas.localbackend','ProgramArguments':[sys.executable,'-m','atlas.server'],
      'WorkingDirectory':str(root/'Backend'),'RunAtLoad':True,'KeepAlive':True,'ThrottleInterval':10,
      'EnvironmentVariables':{'PATH':'/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin',
          'ATLAS_DATA_DIR':str(pathlib.Path.home()/'.atlas-ai'),'ATLAS_PORT':'8765','ATLAS_MODEL':'qwen3:4b'},
      'StandardOutPath':str(logs/'backend.log'),'StandardErrorPath':str(logs/'backend-error.log')}
path=pathlib.Path(os.environ['ATLAS_AGENT_PATH']);path.write_bytes(plistlib.dumps(data));path.chmod(0o600)
PY
launchctl bootstrap "gui/$(id -u)" "$agent"
python3 - <<'PY'
import json,time,urllib.request
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
for _ in range(40):
    try:
        with opener.open('http://127.0.0.1:8765/api/native/session',timeout=1) as r: data=json.load(r)
        if data.get('protocol') == 1: break
    except (OSError,ValueError): pass
    time.sleep(.25)
else: raise SystemExit('Backend startet nicht. Siehe ~/Library/Logs/AtlasLocal/backend-error.log')
PY
open "$destination"
echo 'Installiert: ~/Applications/ATLAS Local.app'
echo 'Der lokale Backend-Dienst startet künftig bei Ihrer Anmeldung. DEINSTALLIEREN.command entfernt diesen Dienst, ohne Gesprächsdaten zu löschen.'
echo 'Bitte die alte Atlas-App beenden. In der neuen App: Einstellungen → Verbindung prüfen.'
