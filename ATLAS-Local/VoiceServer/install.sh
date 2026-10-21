#!/bin/bash
# A.T.L.A.S. – eigene KI-Stimme auf dem Mac einrichten (kostenlos, läuft lokal).
# Aufruf im Terminal:  bash install.sh
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST="$HOME/Library/LaunchAgents/de.atlas.voiceserver.plist"
LOG="$HOME/Library/Logs/atlas-voice.log"
PACKAGE="coqui-tts[cpu]==0.28.0"

echo ""
echo "=== A.T.L.A.S. – eigene KI-Stimme ==="
echo "Verwendet wird die freie Sprach-KI XTTS v2 von Coqui."
echo "Lizenz: Coqui Public Model License – kostenlos für private, nicht-kommerzielle Nutzung."
echo "Details: https://coqui.ai/cpml"
read -r -p "Lizenz akzeptieren und installieren? (j/n) " ANSWER
case "$ANSWER" in j|J|y|Y) ;; *) echo "Abgebrochen."; exit 1 ;; esac

# uv (installiert Python und alle Pakete sauber in einem eigenen Bereich)
if command -v uv >/dev/null 2>&1; then
  UV="$(command -v uv)"
elif [ -x "$HOME/.local/bin/uv" ]; then
  UV="$HOME/.local/bin/uv"
else
  echo "Installiere uv …"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  UV="$HOME/.local/bin/uv"
fi

echo "Lade Python und die Sprach-KI (beim ersten Mal 10–20 Minuten, ca. 4 GB) …"
COQUI_TOS_AGREED=1 "$UV" run --python 3.11 --with "$PACKAGE" python -c "import TTS; print('Pakete bereit.')"

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>de.atlas.voiceserver</string>
  <key>ProgramArguments</key>
  <array>
    <string>$UV</string><string>run</string><string>--python</string><string>3.11</string>
    <string>--with</string><string>$PACKAGE</string>
    <string>python</string><string>$DIR/atlas_voice_server.py</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>COQUI_TOS_AGREED</key><string>1</string>
    <key>PYTORCH_ENABLE_MPS_FALLBACK</key><string>1</string>
    <key>PATH</key><string>$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
  <key>WorkingDirectory</key><string>$DIR</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PLISTEOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo ""
echo "Fertig! Die Stimme startet jetzt im Hintergrund und künftig automatisch mit dem Mac."
echo "Beim ersten Start lädt sie das Sprachmodell (ca. 2 GB) – das dauert einige Minuten."
echo "Fortschritt ansehen:  tail -f \"$LOG\"   (beenden mit ctrl+C)"
echo "Bereit, sobald dort steht: „A.T.L.A.S.-Stimme läuft auf Port 5002“."
echo ""
echo "Eigene Stimme: eine klare Hörprobe (6–30 s) als „stimme.wav“ in diesen Ordner legen:"
echo "  $DIR"
echo "und die Stimme neu starten:  launchctl kickstart -k gui/\$(id -u)/de.atlas.voiceserver"
