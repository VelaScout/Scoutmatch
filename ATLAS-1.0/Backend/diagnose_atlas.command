#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
echo 'Atlas vorher beenden. Dieser Test nutzt echte lokale Modelle; er kann einige Minuten dauern.'
echo 'Testfragen sind synthetisch. Dein Chat und dein Gedächtnis werden weder gelesen noch geändert.'
python3 -W error::ResourceWarning -m unittest discover -s tests -v
python3 -m atlas.doctor --benchmark --compare --audio --output "$HOME/Desktop/Atlas-Diagnose-$(date +%Y%m%d-%H%M%S).json"
