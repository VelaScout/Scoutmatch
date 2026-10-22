"""Welche lokalen Sprachmodelle passen auf diesen Mac? Grundlage für MODELLE_VERGLEICHEN.command.

Die Auswahl richtet sich nach dem Arbeitsspeicher. Größenangaben sind ungefähre Downloadgrößen (Q4) der
Ollama-Bibliothek; was ein Modell auf IHREM Mac taugt, misst erst der Vergleich mit den 25 Arbeitsaufgaben
(atlas.realtests --compare). Nichts hier ist eine gemessene Leistungsangabe.

Aufruf: python3 -m atlas.models [--ram GB]   → druckt die vorgeschlagenen Modelle (eine Zeile je Modell)
"""
from __future__ import annotations

import argparse
import platform
import subprocess

# (Name in Ollama, ca. Download GB, mindestens RAM GB, Werkzeuge in Ollama, Hinweis)
CANDIDATES = [
    ('qwen3:4b-instruct-2507-q4_K_M', 2.5, 8, True, 'schnell, Standard von ATLAS'),
    ('qwen3:8b', 5.2, 16, True, 'gründlicher, langsamer'),
    ('llama3.1:8b', 4.9, 16, True, 'Meta Llama, Deutsch etwas schwächer'),
    ('mistral-nemo', 7.1, 16, True, 'Mistral 12B, gutes Deutsch'),
    ('gemma3:12b', 8.1, 16, False, 'Google Gemma, sehr gutes Deutsch, in Ollama ohne Werkzeugaufrufe'),
    ('qwen3:14b', 9.3, 24, True, 'deutlich stärker, braucht 24 GB+'),
    ('gpt-oss:20b', 14.0, 24, True, 'OpenAI Open-Weight, braucht 24 GB+'),
    ('qwen3:30b-a3b', 19.0, 32, True, 'MoE, schnell für seine Größe, braucht 32 GB+'),
    ('qwen3:32b', 20.0, 48, True, 'sehr stark, braucht 48 GB+'),
    ('llama3.3:70b', 43.0, 64, True, 'sehr stark, braucht 64 GB+, langsam'),
]


def ram_gb() -> int | None:
    if platform.system() != 'Darwin':
        return None
    try:
        done = subprocess.run(['sysctl', '-n', 'hw.memsize'], capture_output=True, text=True, timeout=5)
        return round(int(done.stdout.strip()) / 2**30)
    except (OSError, ValueError, subprocess.SubprocessError):
        return None


def candidates_for(ram: int, limit: int = 5) -> list[tuple]:
    """Die größten sinnvollen Modelle zuerst ausschließen, die nicht in den Speicher passen; Werkzeugfähige bevorzugen."""
    fitting = [c for c in CANDIDATES if c[2] <= ram]
    with_tools = [c for c in fitting if c[3]]
    without = [c for c in fitting if not c[3]]
    chosen = with_tools[:1] + sorted(with_tools[1:], key=lambda c: -c[1])[:limit - 2] + without[:1]
    return chosen[:limit]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--ram', type=int)
    args = parser.parse_args()
    ram = args.ram or ram_gb() or 16
    for name, size, _, tools, note in candidates_for(ram):
        print(f'{name}\t{size}\t{"ja" if tools else "nein"}\t{note}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
