#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo 'Für Apple-Silicon-macOS vorgesehen.'; exit 1; }
command -v brew >/dev/null || { echo 'Homebrew fehlt. Offizielle Installation: https://brew.sh'; exit 1; }
for formula in python ollama ffmpeg whisper-cpp; do
  brew list --formula "$formula" >/dev/null 2>&1 || brew install "$formula"
done
if ! curl --noproxy '*' -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  brew services start ollama
fi
ready=0
for i in {1..30}; do
  if curl --noproxy '*' -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
[[ "$ready" == 1 ]] || { echo 'Ollama startet nicht. Bitte Ollama öffnen und erneut versuchen.'; exit 1; }
ollama pull qwen3:4b
mkdir -p "$HOME/.atlas-ai/models"
export ATLAS_WHISPER_MODEL="${ATLAS_WHISPER_MODEL:-$HOME/.atlas-ai/models/ggml-base.bin}"
if [[ ! -s "$ATLAS_WHISPER_MODEL" ]]; then
  mkdir -p "$(dirname "$ATLAS_WHISPER_MODEL")"
  curl --fail --location --retry 3 https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin -o "$ATLAS_WHISPER_MODEL.partial"
  mv "$ATLAS_WHISPER_MODEL.partial" "$ATLAS_WHISPER_MODEL"
fi
python3 -W error::ResourceWarning -m unittest discover -s tests -v
python3 -m atlas.doctor
echo 'Installation abgeschlossen. Start: bash start_atlas.command'
