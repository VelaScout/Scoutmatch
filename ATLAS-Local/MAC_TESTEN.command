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
(cd Backend && "$python_bin" -m atlas.realtests --output ../build/MAC-ECHTE-MODELLTESTS.json) || echo 'Echte Modelltests: nicht alle bestanden – Details oben und in build/MAC-ECHTE-MODELLTESTS.json'
echo '== 4. Diagnose: Werkzeuge, Antwortzeiten, Spracherkennung (synthetische Stimme, kein Mikrofon)'
(cd Backend && "$python_bin" -m atlas.doctor --benchmark --compare --audio --output ../build/MAC-DIAGNOSE.json) || true
echo 'Details: build/MAC-TESTS.txt, build/MAC-ECHTE-MODELLTESTS.json, build/MAC-DIAGNOSE.json'
(cd Backend && "$python_bin" -m atlas.summary ../build)
