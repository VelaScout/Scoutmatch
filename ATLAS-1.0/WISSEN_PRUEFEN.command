#!/bin/bash
set -e
cd "$(dirname "$0")"
echo 'ATLAS Wissensbibliothek – Qualitätsprüfung (offline)'
python3 Backend/tools/wissen_audit.py
read -r -p 'Enter zum Schließen ...' _
