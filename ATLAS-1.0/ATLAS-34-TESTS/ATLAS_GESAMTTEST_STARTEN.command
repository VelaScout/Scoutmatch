#!/bin/bash
cd "$(dirname "$0")" || exit 1
python3 atlas_gesamt_test.py "$@"
printf '
Enter zum Schließen ...'; read -r _
