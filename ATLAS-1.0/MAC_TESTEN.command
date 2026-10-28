#!/bin/bash
set -uo pipefail   # bei einzelnen Fehlschlägen weitermachen – die Zusammenfassung zeigt alles
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export OLLAMA_HOST=127.0.0.1:11434
source Scripts/backend_common.sh
mkdir -p build
exec > >(tee build/MAC-TESTS.txt) 2>&1
python_bin="$ATLAS_VENV/bin/python3"
[[ -x "$python_bin" ]] || python_bin=python3
echo '== 1. Swift ⇄ Backend (echter Server, simuliertes Modell) und Sprachtext'
bash Tests/test_provider_mac.sh
echo '== 2. Backend-Tests (Werkzeuge mit echten Dateien, Agent-Protokoll, Sicherheit)'
(cd Backend && "$python_bin" -W error::ResourceWarning -m unittest discover -s tests -v)
echo '== 3. ECHTE Modelltests (Qwen über Ollama, Ergebnisse werden in Dateien nachgeprüft)'
# Sind mehrere Modelle installiert, werden sie verglichen und das beste wird als Standard eingetragen.
(cd Backend && "$python_bin" -m atlas.realtests --compare --apply --output ../build/MAC-ECHTE-MODELLTESTS.json) || echo 'Echte Modelltests: nicht alle bestanden – Details oben und in build/MAC-ECHTE-MODELLTESTS.json'
echo '== 4. Diagnose: Werkzeuge, Antwortzeiten, Spracherkennung (synthetische Stimme, kein Mikrofon)'
(cd Backend && "$python_bin" -m atlas.doctor --benchmark --compare --audio --output ../build/MAC-DIAGNOSE.json) || true
echo '== 5. Sandbox-Selbstprüfung (macOS sandbox-exec: Schreibschutz, Internet gesperrt, localhost)'
(cd Backend && "$python_bin" -c 'import json, atlas.sandbox as s; print(json.dumps(s.status(), ensure_ascii=False))' | tee ../build/MAC-SANDBOX.json) || true
echo '== 6. Neustart des Atlas-Dienstes: bleiben Gedächtnis, Erfahrungen und Aufgaben erhalten?'
if launchctl print "gui/$(id -u)/$ATLAS_LABEL" >/dev/null 2>&1; then
  (cd Backend && "$python_bin" -m atlas.persistence_check count ../build/vorher.json)
  launchctl kickstart -k "gui/$(id -u)/$ATLAS_LABEL" && atlas_verify_service
  (cd Backend && "$python_bin" -m atlas.persistence_check count ../build/nachher.json &&
    "$python_bin" -m atlas.persistence_check compare ../build/vorher.json ../build/nachher.json ../build/MAC-NEUSTART.json) || true
else
  echo 'NICHT AUSGEFÜHRT: Atlas-Dienst ist nicht installiert (zuerst INSTALLIEREN.command).'
  echo '{"status": "NICHT AUSGEFÜHRT"}' > build/MAC-NEUSTART.json
fi
echo 'Details: build/MAC-TESTS.txt, build/MAC-ECHTE-MODELLTESTS.json, build/MAC-DIAGNOSE.json'
(cd Backend && "$python_bin" -m atlas.summary ../build)
