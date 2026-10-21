#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export OLLAMA_HOST=127.0.0.1:11434
mkdir -p build
exec > >(tee build/MAC-TESTS.txt) 2>&1
bash Tests/test_provider_mac.sh
(cd Backend && python3 -W error::ResourceWarning -m unittest discover -s tests -v)
# Avoid concurrent real-model generation in the app during this benchmark.
(cd Backend && python3 -m atlas.doctor --benchmark --compare --audio --output ../build/MAC-DIAGNOSE.json)
echo 'Automatische Mac-Prüfungen abgeschlossen. Mikrofon, Berechtigungen, Klang und native Oberfläche bitte anhand TESTBERICHT.md prüfen.'
