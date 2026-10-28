#!/bin/bash
cd "$(dirname "$0")" || exit 1
python3 6_PRAXISTEST_KORRIGIERT.py
code=$?
printf "\nRueckgabecode: %s\nEnter zum Schliessen ..." "$code"
read -r _
exit "$code"
