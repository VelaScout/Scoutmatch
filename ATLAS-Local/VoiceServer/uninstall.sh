#!/bin/bash
# Entfernt den automatischen Start der A.T.L.A.S.-Stimme.
PLIST="$HOME/Library/LaunchAgents/de.atlas.voiceserver.plist"
launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
echo "Die A.T.L.A.S.-Stimme startet nicht mehr automatisch."
