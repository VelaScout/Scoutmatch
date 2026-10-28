#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
python3 -m atlas.doctor --core
exec python3 -m atlas.launch
