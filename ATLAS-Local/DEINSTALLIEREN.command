#!/bin/bash
set -euo pipefail
label=de.atlas.localbackend
launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
agent="$HOME/Library/LaunchAgents/$label.plist"
if [[ -f "$agent" ]]; then mv "$agent" "$agent.disabled-$(date +%Y%m%d-%H%M%S)"; fi
echo 'Atlas-Backend-Autostart entfernt. App, Modelle, Sicherungen und Gesprächsdaten bleiben erhalten.'
echo 'Ollama läuft als eigener Dienst weiter. Bei Bedarf: brew services stop ollama'
