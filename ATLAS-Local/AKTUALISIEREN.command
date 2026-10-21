#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
[[ "$(uname -s)" == Darwin ]] || { echo 'Dieses Update benötigt macOS.'; exit 1; }
if pgrep -x ATLAS >/dev/null 2>&1; then echo 'Bitte Atlas zuerst über die Menüleiste beenden und Update erneut öffnen.'; exit 1; fi
install_root="$HOME/Library/Application Support/AtlasLocal"
agent="$HOME/Library/LaunchAgents/de.atlas.localbackend.plist"
[[ -d "$install_root/Backend" && -f "$agent" ]] || { echo 'Vorherige Installation fehlt. Bitte INSTALLIEREN.command verwenden.'; exit 1; }
# Full native build, Swift contract/text tests, then Python regression tests before replacing anything.
bash BAUEN.command
(cd Backend && python3 -W error::ResourceWarning -m unittest discover -s tests -v)
stamp=$(date +%Y%m%d-%H%M%S)
ditto Backend "$install_root/Backend-staging-$stamp"
destination="$HOME/Applications/ATLAS Local.app"
new_app="$HOME/Applications/ATLAS Local-staging-$stamp.app"
ditto build/DerivedData/Build/Products/Release/ATLAS.app "$new_app"
codesign --verify --strict "$new_app"
launchctl bootout "gui/$(id -u)/de.atlas.localbackend" >/dev/null 2>&1 || true
mv "$install_root/Backend" "$install_root/Backend-backup-$stamp"
mv "$install_root/Backend-staging-$stamp" "$install_root/Backend"
if [[ -d "$destination" ]]; then mv "$destination" "$HOME/Applications/ATLAS Local-backup-$stamp.app"; fi
mv "$new_app" "$destination"
launchctl bootstrap "gui/$(id -u)" "$agent"
python3 - <<'PY'
import json,time,urllib.request
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
for _ in range(40):
    try:
        with opener.open('http://127.0.0.1:8765/api/native/session',timeout=1) as r:key=json.load(r)['token']
        req=urllib.request.Request('http://127.0.0.1:8765/api/native/intent',data=b'{"message":"17*23"}',headers={'X-Atlas-Token':key})
        with opener.open(req,timeout=2) as r:answer=json.load(r)
        if answer.get('answer')=='391.':break
    except (OSError,ValueError,KeyError):pass
    time.sleep(.25)
else:raise SystemExit('Dienstprüfung fehlgeschlagen. Siehe ~/Library/Logs/AtlasLocal/backend-error.log')
print('Lokaler Dienst und Rechner geprüft.')
PY
open "$destination"
echo 'Atlas 0.2.3 aktualisiert. Modelle und Gesprächsdaten wurden nicht ersetzt.'
