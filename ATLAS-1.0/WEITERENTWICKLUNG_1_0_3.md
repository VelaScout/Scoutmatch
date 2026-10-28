# ATLAS 1.0.3 – echte Modellantworten streng bewerten

Diese Version erweitert das vollständige Atlas-1.0.2-Quellprojekt um ein **Live-Qualitätslabor**. Es ruft das lokale ATLAS-Backend auf Port 8765 mit gültigem Sitzungstoken auf und bewertet zehn Aufgaben mit den vorhandenen strengeren `quality_checks`-Regeln. Es verändert die installierte Mac-App nicht.

## Ausführen

ATLAS und Ollama starten. Dann `ATLAS_103_LIVE_TEST.command` doppelklicken. Die Dateien `Ergebnisse/ATLAS_103_QUALITAET.md` und `.json` anschließend im Chat hochladen.

## Grenzen

Der Test verwendet einen festgelegten Systemprompt; er ist kein Test der tatsächlichen Swift-Gesprächskette. Er prüft keine XTTS-Audioausgabe, kein Mikrofon, keine Mac-Aktionen und kein langfristiges Gedächtnis. Regelbasierte Bewertungen sind keine umfassende semantische Intelligenzmessung. Ohne Mac ist hier kein echter Qwen-Modelltest möglich.
