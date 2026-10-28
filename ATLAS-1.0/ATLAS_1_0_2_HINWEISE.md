# Atlas 1.0.2 – Qualitätsprüfungen

Dieses Paket baut auf Atlas 1.0.1 auf. Es ergänzt eine **strenge, deterministische Testsuite** für bekannte Fehler in Gesprächsantworten: ausschließliche Zahlen, Reihenfolge, widersprüchliche Geschwisteraussagen, englische Selbstvorstellung, erfundene Zahlen, Kontext und Aktionswahrheit.

**Keine neue macOS-App kompiliert.** Die neuen Prüfungen laufen unabhängig vom Modell; sie belegen, dass die Prüfregeln funktionieren, nicht, dass Qwen3 sie bereits erfüllt. Die Prüfungen ändern weder laufende Antworten noch Mac-Dateien.

Auf dem Mac: `ATLAS_102_QUALITAETSTEST.command` starten. Die vorhandene Installationsroutine kann weiterhin für das vollständige Projekt verwendet werden. Nächster Schritt: Live-Antworten mit den neuen Regeln bewerten und den Gesprächs-Prompt iterativ verbessern.
