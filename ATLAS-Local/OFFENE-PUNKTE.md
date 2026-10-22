# Grenzen, bekannte Fehler und nächste Schritte – ATLAS Local 0.8.0

## Nicht nachgewiesen (läuft erst auf Ihrem Mac)

- **Xcode-Build 0.8.0.** Neu sind die Cloud-Einstellungen, der Passwortfilter in Swift und die Herkunftsanzeige im Gedächtnis. Die Syntax ist geprüft, nicht kompiliert. Schlägt der Build fehl, stoppt das Update, bevor es etwas ersetzt.
- **Leistung des echten Modells bei den 25 Arbeitsaufgaben.** Zuletzt gemessen: 0.4.0 bestand 6 von 12. Neuere Ergebnisse von Ihrem Mac liegen mir nicht vor.
- **macOS-Sandbox.** Das Profil wird jetzt vor Gebrauch geprüft. Ob eine der Varianten auf Ihrem macOS greift, zeigt `MAC_TESTEN.command` (Schritt 5). Greift keine:
  - Selbst entwickelte Fähigkeiten laufen dann nicht. Das ist absichtlich: ohne Schutz kein Start.
  - Die Code-Werkstatt bleibt dann aus.
- **Antwortzeiten.** Es gibt keine gemessenen Werte für 0.8.0. Die Messung trennt jetzt erste Rückmeldung und vollständiges Ergebnis.
- **Sprache.** Mikrofon, „Atlas“, Unterbrechen und Stimme sind in 0.8.0 unverändert und nicht neu geprüft. Englische Wörter in deutschen Sätzen werden nur korrekt ausgesprochen, wenn das Modell sie als Englisch markiert.
- **Lernaufträge mit dem echten Modell** („Lerne, wie man …“, „Lerne alles über …“): Der Ablauf ist getestet. Ob das 4B-Modell brauchbaren Code oder brauchbare Auszüge liefert, ist offen.

## Bekannte Grenzen

1. **Intelligenz:** Das lokale 4B-Modell ist weit von großen Cloud-Modellen entfernt.
   - Lange, unklare oder sehr verschachtelte Aufträge können scheitern. ATLAS meldet das dann.
   - Für schwierige Aufgaben gibt es die optionale Cloud.
2. **Dokumentlayout:**
   - Word, PDF und PowerPoint entstehen mit klarem, einfachem Layout: Überschriften, Absätze, Aufzählungen, Tabellen.
   - Professionelle Gestaltung mit Logos, Spalten oder Vorlagen gibt es nicht.
   - Beim Ändern von Word ersetzt ATLAS ganze Absätze. Gemischte Formatierung innerhalb eines geänderten Absatzes (z. B. ein fettes Wort) geht dort verloren. Die Sicherung bleibt erhalten.
3. **Recherche:**
   - Sie nutzt die DuckDuckGo-HTML-Suche. Ändert DuckDuckGo das Format, findet sie nichts mehr, und ATLAS meldet das.
   - Die Quellenprüfung erkennt erfundene Adressen, aber keine falsch wiedergegebenen Inhalte. Deshalb stehen die Quellen immer dabei.
4. **Doppelschutz:**
   - Er greift bei inhaltlich identischen Aktionen binnen 24 Stunden.
   - Eine leicht umformulierte zweite Nachricht gilt als neue Nachricht.
5. **Passworterkennung:**
   - Sie folgt festen Mustern („Passwort ist …“, „PIN: …“, Schlüssel- und Kartenformate).
   - Ein Passwort ohne solches Stichwort, z. B. „merk dir: Hund123“, erkennt sie nicht.
6. **Cloud:**
   - Die Kosten sind Listenpreise in US-Dollar, berechnet aus den gemeldeten Token. Steuern und Ihre Rechnung können abweichen.
   - Bei einer Ablehnung durch das Cloud-Modell springt automatisch das von Anthropic empfohlene Ersatzmodell ein. Dessen Abschnitt wird mit seinem eigenen Preis berechnet.
   - Antworten der Cloud werden nicht gestreamt, sie erscheinen am Stück.
7. **Code-Werkstatt:** Übernommene Änderungen am eigenen Code ersetzt ein späteres Update wieder durch die ausgelieferte Version. Selbst entwickelte Fähigkeiten bleiben dagegen erhalten.
8. **Hintergrundarbeit:**
   - Lernzyklen sind anfangs aus.
   - Es gibt ein Tageslimit für die Rechenzeit, aber kein eigenes Arbeitsspeicher-Limit pro Auftrag, weil macOS es für Python nicht zuverlässig durchsetzt.
   - Lernaufträge laufen nur, wenn ATLAS gerade nicht antwortet.
9. **Kein Modelltraining** (bewusst; siehe `docs/FINE-TUNING-STUDIE.md`).
10. **iPhone:** Es gibt keinen Zugriff auf den Mac-Agenten. Der Dienst lauscht nur lokal.

## Nächste Schritte (Empfehlung)

1. Update installieren, dann `MAC_TESTEN.command` laufen lassen und **einen Screenshot der Zusammenfassung** schicken.
   - Daran sehe ich, welche Arbeitsaufgaben das echte Modell schafft und wie schnell es ist.
   - Ich sehe auch, ob Sandbox und Neustart funktionieren.
2. Für jede FEHLGESCHLAGENE Aufgabe gezielt nachschärfen: Werkzeugbeschreibung, höherwertiges Werkzeug oder anderes Modell. Danach erneut messen.
3. Optional die Cloud einrichten und mit einem Monatslimit von wenigen Dollar ausprobieren.
