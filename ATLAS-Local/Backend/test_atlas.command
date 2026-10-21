#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
python3 -W error::ResourceWarning -m unittest discover -s tests -v
python3 -m atlas.doctor
