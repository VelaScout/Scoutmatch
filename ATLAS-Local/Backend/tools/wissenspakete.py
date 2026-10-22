#!/usr/bin/env python3
"""Kompatibler Aufruf wie in WISSENSPAKETE-START.md beschrieben: python3 Backend/tools/wissenspakete.py …"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from atlas.wissenspakete import main  # noqa: E402

if __name__ == '__main__':
    sys.exit(main())
