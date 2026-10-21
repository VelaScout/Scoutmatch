"""A.T.L.A.S. – eigene KI-Stimme auf dem Mac (kostenlos, läuft lokal).

Ein kleiner Sprach-Server mit der freien Sprach-KI XTTS v2 (Coqui). A.T.L.A.S. schickt ihm
Text und bekommt natürlich klingende Sprache als Strom zurück – ohne Cloud, ohne laufende Kosten.

- Eigene Stimme: Legen Sie eine Hörprobe als „stimme.wav“ (6–30 Sekunden, klar gesprochen,
  ohne Musik) in diesen Ordner – XTTS bildet die Stimme daraus nach.
- Ohne Hörprobe wird eine der eingebauten Studio-Stimmen verwendet.

Schnittstelle:
  GET  /health  -> {"ok": true, "voices": [...], "default": "..."}
  POST /tts     {"text": "...", "language": "de", "voice": "optional"}
                -> rohes PCM (24 kHz, 16 Bit, Mono), gestreamt, während es entsteht
"""

from __future__ import annotations

import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import numpy as np
import soundfile as sf
import torch
import torchaudio

HERE = Path(__file__).resolve().parent
OWN_VOICE = HERE / "stimme.wav"
PORT = int(os.environ.get("ATLAS_VOICE_PORT", "5002"))
SAMPLE_RATE = 24_000
PREFERRED_DEFAULTS = ["Damien Black", "Viktor Eka", "Craig Gutsy", "Andrew Chipper"]


def log(message: str) -> None:
    print(time.strftime("%H:%M:%S"), message, flush=True)


# Hörproben mit soundfile laden – so wird kein FFmpeg benötigt.
import TTS.tts.models.xtts as xtts_module  # noqa: E402


def _load_audio(path, sampling_rate):
    data, rate = sf.read(str(path), dtype="float32", always_2d=True)
    audio = torch.from_numpy(data.T.copy())
    if audio.size(0) != 1:
        audio = audio.mean(dim=0, keepdim=True)
    if rate != sampling_rate:
        audio = torchaudio.functional.resample(audio, rate, sampling_rate)
    return audio.clamp(-1, 1)


xtts_module.load_audio = _load_audio

from TTS.api import TTS  # noqa: E402


class Voice:
    """Lädt XTTS einmal und erzeugt Sprache – immer nur eine Anfrage gleichzeitig."""

    def __init__(self) -> None:
        log("Lade XTTS v2 … (beim ersten Start wird das Modell heruntergeladen, ca. 2 GB)")
        api = TTS("tts_models/multilingual/multi-dataset/xtts_v2", progress_bar=True)
        self.model = api.synthesizer.tts_model
        self.device = self._pick_device()
        self.lock = threading.Lock()
        self.latents: dict[str, tuple[torch.Tensor, torch.Tensor]] = {}
        manager = getattr(self.model, "speaker_manager", None)
        self.builtin = list(manager.speakers.keys()) if manager else []
        self.default = "eigene" if OWN_VOICE.exists() else next(
            (name for name in PREFERRED_DEFAULTS if name in self.builtin), self.builtin[0] if self.builtin else "eigene"
        )
        log(f"Bereit auf {self.device}. Standardstimme: {self.default}")

    def _pick_device(self) -> str:
        if os.environ.get("ATLAS_VOICE_DEVICE"):
            device = os.environ["ATLAS_VOICE_DEVICE"]
        elif torch.backends.mps.is_available():
            device = "mps"
        else:
            device = "cpu"
        try:
            self.model.to(device)
            return device
        except Exception as error:  # noqa: BLE001
            log(f"{device} nicht nutzbar ({error}) – nutze CPU")
            self.model.to("cpu")
            return "cpu"

    def voices(self) -> list[str]:
        return (["eigene"] if OWN_VOICE.exists() else []) + self.builtin

    def conditioning(self, voice: str):
        if voice not in self.latents:
            if voice == "eigene" and OWN_VOICE.exists():
                self.latents[voice] = self.model.get_conditioning_latents(audio_path=[str(OWN_VOICE)])
            else:
                name = voice if voice in self.builtin else self.default
                gpt, speaker = self.model.speaker_manager.speakers[name].values()
                self.latents[voice] = (gpt, speaker)
        return self.latents[voice]

    def stream(self, text: str, language: str, voice: str):
        gpt, speaker = self.conditioning(voice or self.default)
        for chunk in self.model.inference_stream(
            text, language, gpt, speaker, stream_chunk_size=20, enable_text_splitting=True
        ):
            audio = chunk.detach().float().cpu().numpy().reshape(-1)
            yield (np.clip(audio, -1, 1) * 32767).astype("<i2").tobytes()


VOICE: Voice | None = None


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args) -> None:  # leiser
        pass

    def _json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if self.path.startswith("/health"):
            self._json(200, {"ok": True, "voices": VOICE.voices(), "default": VOICE.default})
        else:
            self._json(404, {"error": "unbekannt"})

    def do_POST(self) -> None:
        if not self.path.startswith("/tts"):
            self._json(404, {"error": "unbekannt"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            request = json.loads(self.rfile.read(length) or b"{}")
            text = str(request.get("text", "")).strip()
            language = str(request.get("language", "de"))[:2] or "de"
            voice = str(request.get("voice", "") or "")
        except Exception:  # noqa: BLE001
            self._json(400, {"error": "ungültige Anfrage"})
            return
        if not text:
            self._json(400, {"error": "kein Text"})
            return

        self.send_response(200)
        self.send_header("Content-Type", "audio/pcm")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
        started = time.time()
        try:
            with VOICE.lock:
                for pcm in VOICE.stream(text, language, voice):
                    self.wfile.write(f"{len(pcm):X}\r\n".encode() + pcm + b"\r\n")
                    self.wfile.flush()
            self.wfile.write(b"0\r\n\r\n")
            log(f"{len(text)} Zeichen in {time.time() - started:.1f} s")
        except (BrokenPipeError, ConnectionResetError):
            log("Abgebrochen (A.T.L.A.S. wurde unterbrochen)")


def main() -> None:
    global VOICE
    VOICE = Voice()
    # Kurz aufwärmen, damit die erste echte Antwort schnell kommt. Klappt der Grafikchip (MPS)
    # nicht, auf den Prozessor ausweichen.
    try:
        for _ in VOICE.stream("Hallo.", "de", VOICE.default):
            pass
    except Exception as error:  # noqa: BLE001
        if VOICE.device == "cpu":
            raise
        log(f"Grafikchip macht Probleme ({error}) – nutze CPU")
        VOICE.model.to("cpu")
        VOICE.device = "cpu"
        VOICE.latents.clear()
        for _ in VOICE.stream("Hallo.", "de", VOICE.default):
            pass
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    log(f"A.T.L.A.S.-Stimme läuft auf Port {PORT}. Stimmen: {', '.join(VOICE.voices()[:6])} …")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        sys.exit(0)


if __name__ == "__main__":
    main()
