#!/bin/bash
# Gemeinsame Schritte für INSTALLIEREN.command und AKTUALISIEREN.command.
# Wird mit "source" eingebunden; erwartet set -euo pipefail im Aufrufer.

ATLAS_LABEL=de.atlas.localbackend
ATLAS_INSTALL_ROOT="$HOME/Library/Application Support/AtlasLocal"
ATLAS_AGENT_PLIST="$HOME/Library/LaunchAgents/$ATLAS_LABEL.plist"
ATLAS_VENV="$ATLAS_INSTALL_ROOT/venv"

# Eigene Python-Umgebung für das Backend (Excel, PDF, PowerPoint, Word), unabhängig vom System.
# Feste Werkzeuge für PDF, Word, PowerPoint, Excel. anthropic: nur für das optionale, standardmäßig
# ausgeschaltete Cloud-Modell (ohne Aktivierung und Schlüssel wird es nie benutzt).
atlas_setup_venv() {
  mkdir -p "$ATLAS_INSTALL_ROOT"
  if [[ ! -x "$ATLAS_VENV/bin/python3" ]]; then
    echo 'Lege die Python-Umgebung für Atlas an …'
    python3 -m venv "$ATLAS_VENV"
  fi
  "$ATLAS_VENV/bin/python3" -m pip install --quiet --disable-pip-version-check \
    'openpyxl==3.1.5' 'pypdf==6.17.0' 'python-pptx==1.0.2' 'python-docx==1.2.0' 'reportlab>=4.0,<5' 'anthropic==1.17.0'
  "$ATLAS_VENV/bin/python3" -c 'import openpyxl, pypdf, pptx, docx, reportlab, anthropic, sys; assert sys.version_info >= (3, 10)'
  echo 'Python-Umgebung bereit (Excel, PDF, PowerPoint, Word).'
}

# Empfohlene lokale Modelle:
# - qwen3:4b-instruct-2507 (schnelle Antworten OHNE Denkschritt – „qwen3:4b“ ist bei Ollama inzwischen
#   womöglich die Denk-Variante, die vor jeder Antwort sekundenlang ein Selbstgespräch schreibt)
# - nomic-embed-text (Gedächtnissuche)
# - optional qwen3:8b (ATLAS_WITH_8B=1): größer, langsamer; MAC_TESTEN vergleicht es und nimmt das bessere
# Mit ATLAS_SKIP_MODELS=1 überspringen.
atlas_has_model() { ollama list 2>/dev/null | awk '{print $1}' | grep -Eqx "${1}(:latest)?"; }
atlas_pull_models() {
  if [[ "${ATLAS_SKIP_MODELS:-0}" == 1 ]]; then echo 'Modelldownload übersprungen (ATLAS_SKIP_MODELS=1).'; return; fi
  local free_gb
  free_gb=$(df -g "$HOME" | awk 'NR==2 {print $4}')
  if ! atlas_has_model 'qwen3:4b-instruct-2507-q4_K_M' && ! atlas_has_model 'qwen3:4b-instruct'; then
    echo 'Lade schnelles Antwortmodell qwen3:4b-instruct (ca. 2,5 GB, einmalig) …'
    ollama pull qwen3:4b-instruct-2507-q4_K_M || ollama pull qwen3:4b-instruct \
      || { echo 'Hinweis: Schnelles Modell nicht verfügbar – Atlas nutzt qwen3:4b.'; atlas_has_model qwen3:4b || ollama pull qwen3:4b || true; }
  fi
  local models='nomic-embed-text'
  [[ "${ATLAS_WITH_8B:-0}" == 1 ]] && models="$models qwen3:8b"
  for model in $models; do
    if atlas_has_model "$model"; then continue; fi
    if [[ "$model" == qwen3:8b && "${free_gb:-0}" -lt 12 ]]; then
      echo "Nur ${free_gb} GB frei – qwen3:8b (ca. 5 GB) wird nicht geladen. Atlas nutzt dann das 4B-Modell auch für Aufgaben."
      continue
    fi
    echo "Lade lokales Modell $model (einmalig) …"
    ollama pull "$model" || echo "Hinweis: $model konnte nicht geladen werden. Atlas funktioniert mit den vorhandenen Modellen weiter."
  done
  # Optional: Bildmodell für Bildschirm- und Bildanalyse (ca. 3 GB): ATLAS_WITH_VISION=1
  if [[ "${ATLAS_WITH_VISION:-0}" == 1 ]] && ! ollama list 2>/dev/null | awk '{print $1}' | grep -Eqx 'gemma3:4b'; then
    echo 'Lade Bildmodell gemma3:4b …'
    ollama pull gemma3:4b || echo 'Hinweis: Bildmodell konnte nicht geladen werden.'
  fi
}

# Autostart des Backends bei der Anmeldung, mit der eigenen Python-Umgebung.
atlas_write_agent() {
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/AtlasLocal"
  ATLAS_INSTALL_ROOT="$ATLAS_INSTALL_ROOT" ATLAS_AGENT_PLIST="$ATLAS_AGENT_PLIST" ATLAS_VENV="$ATLAS_VENV" \
  "$ATLAS_VENV/bin/python3" - <<'PY'
import os, pathlib, plistlib
root = pathlib.Path(os.environ['ATLAS_INSTALL_ROOT'])
logs = pathlib.Path.home() / 'Library/Logs/AtlasLocal'
data = {'Label': 'de.atlas.localbackend',
        'ProgramArguments': [os.environ['ATLAS_VENV'] + '/bin/python3', '-m', 'atlas.server'],
        'WorkingDirectory': str(root / 'Backend'), 'RunAtLoad': True, 'KeepAlive': True, 'ThrottleInterval': 10,
        'EnvironmentVariables': {'PATH': '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin',
                                 'ATLAS_DATA_DIR': str(pathlib.Path.home() / '.atlas-ai'), 'ATLAS_PORT': '8765',
                                 'ATLAS_MODEL': 'qwen3:4b'},
        'StandardOutPath': str(logs / 'backend.log'), 'StandardErrorPath': str(logs / 'backend-error.log')}
path = pathlib.Path(os.environ['ATLAS_AGENT_PLIST'])
path.write_bytes(plistlib.dumps(data))
path.chmod(0o600)
PY
}

# Prüft den laufenden Dienst: Agent-Protokoll vorhanden und direkte Rechnung korrekt.
atlas_verify_service() {
  "$ATLAS_VENV/bin/python3" - <<'PY'
import json, time, urllib.request
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
for _ in range(60):
    try:
        with opener.open('http://127.0.0.1:8765/api/native/session', timeout=1) as r:
            session = json.load(r)
        request = urllib.request.Request('http://127.0.0.1:8765/api/native/intent', data=b'{"message":"17*23"}',
                                         headers={'X-Atlas-Token': session['token']})
        with opener.open(request, timeout=2) as r:
            answer = json.load(r)
        if session.get('agent') == 2 and answer.get('answer') == '391.':
            print('Lokaler Dienst geprüft: Agent-Protokoll 2 aktiv, Rechner korrekt.')
            break
    except (OSError, ValueError, KeyError):
        pass
    time.sleep(.25)
else:
    raise SystemExit('Dienstprüfung fehlgeschlagen. Siehe ~/Library/Logs/AtlasLocal/backend-error.log')
PY
}
