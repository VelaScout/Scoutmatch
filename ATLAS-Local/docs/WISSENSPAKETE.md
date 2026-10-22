# Wissenspakete – vorbereitete Themen für den Wissensaufbau

Übernommen aus Ihrem Paket „ATLAS-Local-0.8.0_2“ (193 Themen in 15 Fachgebieten) und fest eingebaut.

## Benutzen

**In der App:** Learning & Evolution → Wissen → „Wissenspakete“ → beim gewünschten Fachgebiet „Einreihen“.

**Im Terminal** (im entpackten Projektordner):

```bash
python3 Backend/tools/wissenspakete.py                                   # nur Vorschau
python3 Backend/tools/wissenspakete.py --pakete physik sport --einreihen # einreihen
python3 Backend/tools/wissenspakete.py --pakete alle --einreihen
```

**Ausgeführt** wird erst, wenn in „Learning & Evolution“ die **Lernzyklen eingeschaltet** sind. Dann gilt:
- Es läuft nur im Tageslimit für Rechenzeit (Standard 30 Minuten).
- Es braucht die Erlaubnis für Internetzugriff.
- Es läuft nur, solange ATLAS gerade nicht antwortet.
- Es lässt sich jederzeit pausieren.

Ist das Internet ausgeschaltet, warten die Themen und laufen später weiter. Es geht nichts verloren.

## Was dabei passiert

Jedes Thema durchläuft den Wissensaufbau:
1. Bis zu vier Quellen lesen.
2. Aussagen herausziehen und jede gegen ihren Quelltext prüfen.
3. Mit Quelle, Abrufdatum und Status speichern (belegt / mehrfach belegt / Vermutung / Widerspruch).
4. Lücken notieren.

Spätere Fragen zu diesen Themen beantwortet ATLAS mit Quellenangabe.

## Ehrliche Grenzen

- **Kein Modelltraining:** Neues Wissen liegt in `~/.atlas-ai/atlas.db`, nicht in den Modellgewichten.
- **Kein vollständiges Fachwissen:** Ein Thema mit vier Quellen erschließt kein ganzes Fachgebiet.
- **Fehlschläge möglich:** Ein kleines lokales Modell kann Aussagen falsch zusammenfassen. Deshalb steht jede Aussage mit Quelle da.
- **Laufzeit:** Ein Paket mit rund 12 Themen braucht im Tageslimit von 30 Minuten mehrere Tage.
- **Für sehr große Wissensmengen** (zehntausende Aussagen) ist die einfache Suche nicht ausgelegt. Dafür bräuchte es einen Volltext- oder Vektorindex.
- **Urheberrecht:** Gespeichert werden nur kurze, abgeleitete Aussagen mit Quellenverweis, keine Seitenkopien.

## Gegenüber Ihrem Paket korrigiert

1. **Falsche Auftragsart:** Die Aufträge wurden als `learn_topic` eingetragen. Der Lernplaner kennt nur `topic`, daher wären alle als „fehlgeschlagen“ geendet.
2. **Kein Schalter, kein Limit:** Hintergrundaufträge liefen bisher ohne eingeschaltete Lernzyklen und ohne Tageslimit. Jetzt gelten beide.
3. **Internet aus:** Ohne Internet wurden alle wartenden Themen auf einmal als „blockiert“ markiert und liefen nie wieder. Jetzt warten sie.
