# Grenzen, bekannte Fehler und nächste Schritte – ATLAS 0.9.2

## Ehrlich vorweg: ATLAS und ChatGPT/Claude

ATLAS ist eine echte KI: Ein generatives Sprachmodell formuliert jede Antwort selbst und entscheidet, welche Werkzeuge es nutzt.

Das lokale Modell auf Ihrem Mac (Qwen3 4B, etwa 2,5 GB) ist aber **deutlich schwächer** als ChatGPT oder Claude in der Cloud. Diese laufen auf Rechenzentren mit hundertfach größeren Modellen.

Was ATLAS ausgleicht:
- Werkzeuge, die viel selbst erledigen und ihr Ergebnis prüfen
- Gedächtnis und Erfahrungen
- Recherche mit Quellen
- **optional die Cloud** – damit erreicht er bei schwierigen Aufgaben tatsächlich Claude-Niveau, gegen Kosten

Größere lokale Modelle (14B, 30B) sind deutlich besser, brauchen aber mehr Arbeitsspeicher. `MODELLE_VERGLEICHEN.command` zeigt, was auf Ihrem Mac sinnvoll läuft.

## Nicht nachgewiesen (läuft erst auf Ihrem Mac)

- **Neue Chat-Oberfläche und 3D-Kugel (0.9.1/0.9.2).** Die Syntax ist geprüft, aber nicht kompiliert und nicht angesehen: Wie die Kugel und der Chat auf Ihrem Bildschirm wirken, sehen wir erst auf Ihrem Mac. Gespeicherte Gespräche und das Datenformat sind unverändert.
- **Xcode-Build 0.9.0.** Neu sind die Wissenspakete, der Cloud-Modus und die neue Persona. Die Syntax ist geprüft, nicht kompiliert. Schlägt der Build fehl, stoppt das Update, bevor es etwas ersetzt.
- **Ihr letzter Testlauf (0.8.0)** zeigte:
  - Sandbox und Neustart: in Ordnung.
  - Fehlgeschlagen: markdown_liste, teilweise_fehler, Diagnose „rechnung“.
  - Recherche: nicht ausgeführt.

  Die vermuteten Ursachen sind in 0.8.1/0.9.0 behoben. Ob es jetzt klappt, zeigt erst der nächste Lauf. Den oberen Teil der Zusammenfassung (die ersten Aufgaben und die Zeiten) habe ich nicht gesehen.
- **Recherche auf Ihrem Mac.** Mehrere Suchdienste und certifi sind eingebaut. Ob die Suchdienste automatische Abfragen von Ihrem Mac zulassen, zeigt der nächste Testlauf. Im Fehlerfall steht der genaue Grund dabei.
- **Lernaufträge und Wissenspakete mit dem echten Modell:** Der Ablauf ist getestet, die Qualität der Ergebnisse noch nicht.

## Sprache (Abschnitt 7 Ihres Auftrags) – Stand

| Wunsch | Stand |
|---|---|
| Aktivierungswort „ATLAS“ | vorhanden, über die Apple-Spracherkennung auf dem Gerät |
| Weiterreden ohne neue Aktivierung | vorhanden (Einstellung „Nach einer Antwort weiter zuhören“) |
| Unterbrechen | vorhanden („Stopp“ oder eine neue Frage) |
| Textmodus | vorhanden (Textfeld) |
| Englische Begriffe richtig aussprechen | teilweise: Nur Abschnitte, die das Modell als Englisch markiert, spricht eine englische Stimme |
| **Automatische Erkennung Deutsch/Englisch** | **nicht umgesetzt** – Apple erkennt eine eingestellte Sprache. Geantwortet wird aber in der Sprache der Frage. |
| **Menschlich klingende Stimme** | **teilweise:** Apple-„Premium“-Stimmen klingen gut, sind aber keine neuronale Stimme. Im Projekt liegt ein lokaler XTTS-Sprachserver aus der frühen Version. Er ist ausgeschaltet, weil er ohne Hörtest auf Ihrem Mac nicht geprüft werden kann. Seine Modell-Lizenz (Coqui) erlaubt nur nicht-kommerzielle Nutzung. |
| Schnelle Reaktion | gemessen nur in Ihrem Testlauf (erste Rückmeldung getrennt von der Gesamtzeit) |

Eine neuronale deutsche Stimme (z. B. Piper, MIT-Lizenz) und die Erkennung beider Sprachen gleichzeitig (Whisper) sind der sinnvollste nächste Schritt für die Sprache. Beides braucht einen Hörtest auf Ihrem Mac.

## Bekannte Grenzen

1. **Dokumentlayout:**
   - Word, PDF und PowerPoint entstehen mit klarem, einfachem Layout.
   - PowerPoint kann ATLAS erstellen und lesen, aber nicht bearbeiten. Auf Wunsch entwickelt er das als neue Fähigkeit.
   - Beim Ändern von Word ersetzt ATLAS ganze Absätze; gemischte Formatierung in diesem Absatz geht verloren. Die Sicherung bleibt.
2. **Recherche:**
   - Sie liest öffentliche Webseiten.
   - Die Quellenbewertung ordnet nach Herkunft ein, nicht nach Inhalt.
   - Erfundene Adressen werden entfernt, falsch wiedergegebene Inhalte nicht erkannt. Deshalb stehen die Quellen dabei.
3. **Doppelschutz:** gilt für inhaltlich identische Aktionen binnen 24 Stunden.
4. **Passworterkennung:** folgt festen Mustern („Passwort ist …“, „PIN: …“, Schlüssel- und Kartenformate).
5. **Cloud:**
   - Kosten sind Listenpreise in US-Dollar, berechnet aus den gemeldeten Token.
   - Antworten kommen am Stück, nicht gestreamt.
6. **Code-Werkstatt:** Übernommene Codeänderungen ersetzt ein späteres Update wieder. Selbst entwickelte Fähigkeiten bleiben erhalten.
7. **Hintergrundarbeit:**
   - Lernzyklen und Wissenspakete laufen nur eingeschaltet und im Tageslimit.
   - Es gibt kein eigenes Arbeitsspeicher-Limit pro Auftrag.
8. **Kein Modelltraining** (bewusst; siehe `docs/FINE-TUNING-STUDIE.md`). ATLAS lernt über Gedächtnis, Erfahrungen, Regeln, Wissen und neue Werkzeuge, nicht über die Modellgewichte.
9. **iPhone:** kein Zugriff auf den Mac-Agenten.
10. **Webseiten entwickeln:** ATLAS kann HTML/CSS/JS-Dateien schreiben und prüfen. Veröffentlichen (Hosting) gehört nicht dazu.

## Nächste Schritte (Empfehlung)

1. Update installieren, `MAC_TESTEN.command` laufen lassen und **die ganze Zusammenfassung** schicken (bitte auch den oberen Teil).
2. Optional `MODELLE_VERGLEICHEN.command`: Damit sehen wir, ob ein größeres Modell auf Ihrem Mac spürbar besser ist.
3. Danach: Sprache verbessern (neuronale Stimme, Deutsch und Englisch gleichzeitig), mit Hörtest.
