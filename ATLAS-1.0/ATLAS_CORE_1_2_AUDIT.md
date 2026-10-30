# ATLAS Core 1.2 – Code-Audit und gezielte Reparatur

## Änderungen
- Barge-in: vorherige Spracherkennung wird vor dem Neustart gestoppt.
- Barge-in: kurze Stopp-Kommandos werden von längeren Äußerungen unterschieden.
- Vorhandener 1.1-Fix: vollständiger erkannter Unterbrechungstext statt nur sechs Wörter.
- Siri-Stimme und bestehende Einstellungen bleiben unverändert.

## Wesentliche Einschränkungen
- Unterbrechen per Sprache bleibt aus Datenschutz- und Kompatibilitätsgründen Opt-in.
- Die Funktion benötigt funktionierende Echo-Unterdrückung und kann auf manchen Macs ausfallen.
- Es wurde kein macOS-Build und kein Live-Mikrofon-Test durchgeführt.
- Kein objektiver ChatGPT-/Claude-Gleichstand nachgewiesen.
- Cloudmodelle benötigen gesonderte Konfiguration, Kosten- und Datenschutzfreigabe.

## Empfohlene Mac-Prüfung
1. Vorherige App sichern; Projekt mit BAUEN.command auf dem Mac bauen.
2. In den Einstellungen „Unterbrechen per Stimme“ einschalten.
3. Zehn Unterbrechungen während langer Antworten testen; anschließend zehn normale Antworten ohne Unterbrechung.
4. Auf Rückkopplung, Aussetzer und verlorene Wörter prüfen. Bei Problemen Barge-in wieder ausschalten.
5. Danach einen echten Vergleichstest mit identischen Aufgaben und dokumentierter Latenz durchführen.
