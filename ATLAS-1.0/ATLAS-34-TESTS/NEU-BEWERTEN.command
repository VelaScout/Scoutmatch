#!/bin/bash
cd "$(dirname "$0")" || exit 1
printf '\nATLAS – bisherige Antworten korrekt neu bewerten\n\n'
python3 atlas_gesamt_test.py --rescore
result=$?
printf '\nEnter zum Schließen ...\n'
read -r _
exit "$result"
