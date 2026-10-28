# Was ATLAS 0.9.2 kann – mit Beispielaufträgen

**Geprüft heißt:** Die Werkzeuge und Abläufe sind mit echten Dateien und Prozessen getestet, die Modellentscheidungen dabei simuliert.

**Ob das lokale Qwen-Modell den richtigen Schritt wählt**, zeigt erst `MAC_TESTEN.command` auf Ihrem Mac. Die Spalte „Arbeitsaufgabe“ nennt den Fall dort.

## Gespräch und Wissen

| Auftrag (Beispiel) | Was passiert | Arbeitsaufgabe |
|---|---|---|
| „Was ist 17 mal 23?“, „19 Prozent von 2500“ | Exakte Rechnung ohne Modell | rechnen, prozent |
| „Erkläre mir kurz, was ein Cashflow ist.“ | Kurze Antwort; bei komplexen Fragen ausführlicher | kurze_antwort |
| „What's the capital of Japan?“ | Antwort auf Englisch | englisch |
| „Bist du eine KI?“ | „Ja …“ – ATLAS ist eine KI mit lokalem Sprachmodell | identitaet |
| „Mein Hund heißt Bello und ist drei.“ → „Wie heißt mein Hund, und wie alt ist er?“ | Merkt sich den Gesprächsverlauf | kontext |
| „Anna ist älter als Ben, Ben älter als Clara. Wer ist am jüngsten?“ | Logische Schlüsse | logik |
| „An welchen Tagen habe ich Fußballtraining?“ (wenn gespeichert) | Nutzt gespeicherte Erinnerungen | gedaechtnis |
| „Recherchiere die aktuellen Förderprogramme für Photovoltaik und nenne Quellen.“ | Liest mehrere Seiten. Aussagen sind mit [1], [2] belegt, am Ende stehen die Quellen mit Datum. Nicht abgerufene Adressen werden entfernt. | recherche_quellen |
| „Lerne alles über Unternehmensbewertung.“ | Wissensaufbau im Hintergrund. Jede Aussage hat Quelle und Status (belegt, Vermutung, Widerspruch). | – |
| „Cloud: Analysiere diesen Vertragsentwurf auf Risiken.“ | Nur wenn eingeschaltet. Vorher Rückfrage mit Datenübersicht, danach Kostenangabe. | – (kostet Geld) |
| „Wechsle in den Cloud-Modus“ / „Wechsle in den lokalen Modus“ | Alle Anfragen gehen in die Cloud bzw. bleiben lokal; „Lokal: …“ hält eine einzelne Anfrage auf dem Mac | – |

## Dokumente

| Auftrag | Ergebnis | Arbeitsaufgabe |
|---|---|---|
| „Schreibe ein Angebot an Herrn Müller über eine Webseite für 4.800 € als Word-Dokument.“ | Echte .docx mit Überschriften und Aufzählungen | word_angebot_pdf |
| „Speichere es zusätzlich als PDF.“ | PDF aus der eben erstellten Datei; das Original bleibt | word_angebot_pdf |
| „Ändere in Dokumente/Vertrag.docx die Laufzeit von 12 auf 24 Monate.“ | Nach Bestätigung geändert, vorher gesichert (`~/.atlas-ai/sicherungen`) | word_aendern |
| „Erstelle eine Excel-Tabelle für meine Ausgaben mit Miete 1200 und Strom 90.“ | Echte .xlsx, Formeln möglich | excel |
| „Setze in Budget.xlsx die Zelle B3 auf 95 und füge eine Summenzeile hinzu.“ | Tabelle geändert (mit Bestätigung und Sicherung) | – |
| „Erstelle eine Präsentation mit zwei Folien: Training und Erholung.“ | Echte .pptx | powerpoint_erstellen |
| „Erstelle einen Quartalsbericht als PDF: Umsatz 42.000 €.“ | Echte PDF mit automatischen Seitenumbrüchen | pdf_erstellen |
| „Vergleiche vertrag_alt.txt mit vertrag_neu.docx.“ | Unterschiede Zeile für Zeile, mit Übereinstimmung in Prozent (alle lesbaren Formate) | vergleich |
| „Fasse die PDF Bericht in Dokumente zusammen.“ / „Was steht in Plan.pptx?“ | PDF, Word, Excel, CSV und PowerPoint lesen | pdf_zusammenfassen |
| „Lies ausgaben.csv und sag mir die Summe.“ | Summe mit dem Rechenwerkzeug, nicht im Kopf | csv_summe |

## Dateien und Ordner

| Auftrag | Ergebnis | Arbeitsaufgabe |
|---|---|---|
| „Sortiere meinen Downloads-Ordner nach Dateityp.“ | Unterordner PDF, Bilder, Texte …; nichts wird gelöscht | ordner_sortieren |
| „Welche Datei habe ich gestern bearbeitet?“ | Zuletzt geänderte Dateien | datei_von_gestern |
| „Lösche alt.txt in Dokumente.“ | Nur nach Bestätigung, und dann in den Papierkorb | loeschen_abgelehnt |

## Projekte und Code

| Auftrag | Ergebnis | Arbeitsaufgabe |
|---|---|---|
| „Aufgabe: Im Projekt ~/Code/rechner schlägt ein Test fehl. Finde und behebe den Fehler.“ | Projekt ansehen → Tests (mit Bestätigung) → Stelle ändern → Tests wiederholen → Bericht | fehler_beheben |

## Arbeitsablauf

| Auftrag | Ergebnis |
|---|---|
| „Mach weiter.“ (nach Abbruch oder Neustart) | Setzt die unterbrochene Aufgabe fort und wiederholt nichts Erledigtes |
| „Ändere das“ / „Speichere es als …“ | Bezieht sich auf die zuletzt erzeugte Datei |
| Eine Aufgabe mit einem unmöglichen Teil | Erledigt den möglichen Teil und sagt klar, was fehlgeschlagen und was offen ist (Arbeitsaufgabe: teilweise_fehler) |
| Die gleiche E-Mail oder der gleiche Termin noch einmal | Rückfrage statt doppelter Ausführung |

## Kalender, Erinnerungen, Mail, Apps (über die App)

- „Was steht morgen im Kalender?“, „Trag Zahnarzt Dienstag 10 Uhr ein.“
- „Erinnere mich morgen an die Steuer.“
- „Lies meine neuesten E-Mails.“: nur mit eingerichtetem Mailkonto; Senden nur nach Bestätigung.
- „Öffne Safari“, „Zeig mir Downloads.“

Fehlt eine Kontoverbindung oder Berechtigung, sagt ATLAS das, statt eine Ausführung zu behaupten. Diese Funktionen waren hier nicht testbar (NICHT AUSGEFÜHRT).

## Gedächtnis und Lernen – was es ist und was nicht

| Begriff | Was ATLAS tatsächlich tut |
|---|---|
| **Gedächtnis** | „Merk dir: Ich arbeite montags im Homeoffice.“ wird gespeichert und passt zu späteren Aufgaben. Sie können es ansehen, bearbeiten, exportieren und löschen. Herkunft und Zeitpunkt werden angezeigt. Zugangsdaten werden nie gespeichert. |
| **Wissenssuche** | Recherche mit Quellen und die aufgebaute Wissensbasis, immer mit Quellenangabe |
| **Erlernte Arbeitsabläufe** | Aus geprüften Erfahrungen und Ihren Korrekturen („Nein, speichere so etwas immer in Dokumente.“) |
| **Neue Werkzeuge** | „Ich möchte, dass du … kannst“ / „Lerne, wie man …“: Zuerst prüft ATLAS, ob er es schon kann (z. B. Excel bearbeiten → „Das kann ich bereits“). Sonst Entwicklung und Tests in einer Sandbox; aktiv erst nach Ihrer Freigabe. |
| **Wissenspakete** | 193 vorbereitete Themen aus 15 Fachgebieten (Learning & Evolution → Wissen). Bearbeitet nur mit eingeschalteten Lernzyklen; siehe `docs/WISSENSPAKETE.md`. |
| **Modelltraining** | **Findet nicht statt.** Die Gewichte des Modells ändern sich nicht. Siehe `docs/FINE-TUNING-STUDIE.md`. |

## Bedienung

- **Chat wie bei ChatGPT/Claude (neu in 0.9.1):** Ihre Nachrichten stehen rechts, die Antworten von ATLAS links. Die Antwort erscheint Wort für Wort, während sie entsteht; Fettschrift, Listen und Links werden formatiert.
- **Die Kugel (3D aus leuchtenden Punkten und Quadraten, mit Hologramm-Ringen):** dreht sich ruhig, schlägt beim Zuhören Wellen mit Ihrer Stimme, verdreht sich beim Nachdenken und sendet beim Sprechen Impulse. Antippen = sprechen, lange drücken = Einstellungen.
- **Neuer Chat:** Stift-Knopf oben rechts. Ein leerer Chat zeigt die große Kugel und Vorschläge zum Antippen. Alte Gespräche bleiben im Verlauf (Uhr-Knopf).
- „Atlas …“ sprechen oder ins Textfeld schreiben.
- Die Statuszeile zeigt Dienst, Modell und Mikrofon. Das Aufgabenfeld zeigt jede Aktion.
- Stoppen: Kugel antippen oder Stopp-Knopf. Eine abgebrochene Antwort bleibt sichtbar und ist als „Abgebrochen“ markiert.
- Einstellungen → Darstellung: „Kugel, lebendig“ oder „Kugel, ruhig (besonders sparsam)“.
- Das Mikrofon lässt sich in den Einstellungen abschalten.
