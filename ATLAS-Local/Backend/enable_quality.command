#!/bin/bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
echo 'Lädt optional Qwen3 8B herunter (mehrere GB). Anschließend im Modellmenü auswählen.'
ollama pull qwen3:8b
