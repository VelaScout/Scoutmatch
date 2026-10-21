# Offene Punkte, Grenzen und nächste Entwicklungsstufe – ATLAS Local 0.6.0

## Noch nicht auf echter Hardware bewiesen

| Punkt | Status | Prüfung |
|---|---|---|
| Xcode-Build 0.6.0 (neuer Bereich „Learning & Evolution“, Swift Charts) | Syntax geprüft, nicht kompiliert | `AKTUALISIEREN.command` stoppt bei Fehlern, bevor es etwas ersetzt |
| 16 echte Aufgaben mit `qwen3:4b-instruct` | vorbereitet; 0.4.0 bestand 6/12 | `MAC_TESTEN.command` → Zusammenfassung |
| Fähigkeit mit dem echten Modell entwickeln (z. B. PowerPoint) | Ablauf mit vorgegebenem Code getestet; ob das 4B-Modell brauchbaren Code schreibt, ist offen | „Lerne, wie man PowerPoint-Präsentationen erstellt“ |
| Wissen mit dem echten Modell aufbauen | Ablauf getestet; Qualität der Auszüge offen | „Lerne alles über Unternehmensbewertung“ |
| `sandbox-exec`-Profil der Code-Werkstatt (Netz nur localhost) | nicht ausprobiert; ohne Sandbox laufen keine Werkstatt-Tests | erster Werkstatt-Auftrag auf dem Mac |
| Ansage beim Start („Ich habe eine bessere Methode gefunden …“) | Code geschrieben, nicht gehört | App starten, wenn eine Freigabe offen ist |
| Antwortzeit kurzer Fragen | Ziel unter 2 s; gemessen bisher nur mit der Denk-Variante (9–15 s) | `MAC_TESTEN.command` |
| Mikrofon, Wake-Word, Unterbrechen, Stimme | ungetestet seit 0.5.0 | von Hand |

## Bekannte Grenzen

1. **Intelligenz:** Ein 4B-Modell ist weit von ChatGPT oder Claude entfernt.
   - Selbst entwickelte Fähigkeiten gelingen eher bei einfachen Aufgaben.
   - Scheitert eine Entwicklung, steht das ehrlich in der Liste, und nichts wird aktiv.
2. **Lernen ist Wissen, kein Training:**
   - Erfahrungen, Regeln, Fähigkeiten und Wissen werden gespeichert und genutzt.
   - Die Modellgewichte bleiben gleich. Siehe `docs/FINE-TUNING-STUDIE.md`.
3. **Belegprüfung des Wissens:**
   - Sie erkennt erfundene Aussagen, deren Wörter nicht im Quelltext stehen.
   - Sinnverdrehungen mit denselben Wörtern erkennt sie nicht. Deshalb steht immer die Quelle dabei.
4. **Code-Werkstatt und Updates:** Übernommene Code-Änderungen gelten für das installierte Backend. `AKTUALISIEREN.command` ersetzt es durch die ausgelieferte Version.
5. **Rechenzeit-Limit:**
   - Es gilt für eigenständige Lernzyklen.
   - Ihre ausdrücklichen Lernaufträge laufen ohne Tageslimit, aber pausierbar und abbrechbar.
   - Ein einzelner Modellaufruf wird nicht mitten im Satz unterbrochen, sondern nach dem Schritt.
6. **Speicherlimit:**
   - Lernaufträge laufen nur, wenn ATLAS gerade nicht antwortet. Fähigkeiten haben feste Grenzen für CPU-Zeit, Dateigröße und offene Dateien.
   - Ein eigenes Arbeitsspeicher-Limit pro Auftrag gibt es nicht. macOS setzt es für Python nicht zuverlässig durch.
7. **Stimme, Spracherkennung, Bildschirm, iPhone:** unverändert wie in 0.5.0.
   - Apple-Stimmen.
   - Spracherkennung in einer Sprache.
   - Bildschirm nur mit Bildmodell.
   - Kein iPhone-Zugriff auf den Mac-Agenten.

## Empfehlung für die nächste Entwicklungsstufe

1. **Messen:**
   1. `AKTUALISIEREN.command`
   2. `MAC_TESTEN.command`
   3. Screenshot der Zusammenfassung schicken
2. **Learning & Evolution ausprobieren:**
   1. Einen Lernauftrag für eine Fähigkeit und einen für ein Thema geben.
   2. Nach einigen Minuten das Gehirn-Symbol öffnen.
   3. Screenshot der Liste schicken, auch bei „fehlgeschlagen“: Die Testausgabe zeigt, woran das Modell scheitert.
3. **Gezielt nachschärfen:**
   - Scheitert die Fähigkeitsentwicklung, kann `qwen3:8b` als Entwicklungsmodell helfen. Es ist langsamer, schreibt aber besseren Code.
   - Einschalten mit `"skill_model": "qwen3:8b"` in `~/.atlas-ai/settings.json` (Modell vorher installieren: `ATLAS_WITH_8B=1`).
   - Ohne diesen Eintrag nutzen Lernaufträge das Aufgabenmodell.
4. **Vollständige Werkzeugdialoge speichern:** Grundlage für spätere Verbesserungen und ein mögliches Training.
5. **iPhone:** Zugriff auf den Mac-Agenten über eine gesicherte Verbindung im eigenen WLAN, mit Kopplung per Code.
6. **Stimme:** Piper als optionale, schnellere Stimme mit Hörtest.
