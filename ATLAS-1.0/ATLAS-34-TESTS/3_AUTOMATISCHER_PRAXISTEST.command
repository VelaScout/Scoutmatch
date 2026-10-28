#!/bin/bash
cd "$(dirname "$0")" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
python3 atlas_praxistest_auto.py
code=$?
printf '\nRueckgabecode: %s\nEnter zum Schliessen ... ' "$code"
read -r _
exit "$code"
