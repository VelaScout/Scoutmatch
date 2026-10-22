"""Fähigkeitsübersicht: Was kann ATLAS bereits? Wird vor jedem Lernauftrag geprüft.

„ATLAS, ich möchte, dass du Excel-Dateien bearbeiten kannst.“ → zuerst hier nachsehen. Ist die Fähigkeit
vorhanden, sagt ATLAS das mit Beispielen, statt etwas Neues zu entwickeln. Nur wenn nichts passt (oder
genau die gewünschte Tätigkeit fehlt), entsteht ein Lernauftrag für die Sandbox.
"""
from __future__ import annotations

import re

# (Gegenstand, Tätigkeiten, die NICHT abgedeckt sind, Werkzeuge, Beschreibung mit Beispiel)
CAPABILITIES = [
    (r'excel|xlsx|tabelle|spreadsheet|kalkulation', None, ['create_spreadsheet', 'edit_spreadsheet', 'read_file'],
     'Excel-Tabellen erstellen, lesen und ändern (Zellen, Formeln, neue Zeilen) – z. B. „Erstelle eine Tabelle mit meinen Einnahmen und Ausgaben“.'),
    (r'\bcsv\b', None, ['create_spreadsheet', 'edit_spreadsheet', 'read_file'], 'CSV-Dateien erstellen, lesen und ändern.'),
    (r'\bword\b|docx|brief|angebot|bericht|konzept|dokument', None, ['create_document', 'edit_document', 'read_file'],
     'Word-Dokumente erstellen, lesen und ändern – z. B. „Schreibe ein Angebot als Word-Dokument“.'),
    (r'\bpdf', r'unterschreib|signier|formular ausfüll|schwärz', ['create_pdf', 'read_file', 'convert_document'],
     'PDFs erstellen und lesen und Dokumente in PDF umwandeln.'),
    (r'powerpoint|präsentation|pptx|folien', r'bearbeit|änder|anpass|überarbeit', ['create_presentation', 'read_file'],
     'PowerPoint-Präsentationen erstellen und lesen – z. B. „Erstelle eine Präsentation mit drei Folien zu …“.'),
    (r'vergleich|unterschied', None, ['compare_documents'], 'Zwei Dokumente vergleichen und die Unterschiede zeigen.'),
    (r'recherch|internet|websuche|im web|quellen|nachrichten', None, ['research', 'search_web', 'fetch_webpage'],
     'Im Internet recherchieren, mehrere Quellen lesen und mit Quellenangabe zusammenfassen.'),
    (r'ordner|dateien (sortier|aufräum|organis)|sortier|aufräum', None, ['organize_folder', 'move_path', 'create_folder'],
     'Ordner anlegen und Dateien nach Typ sortieren.'),
    (r'code|programmier|projekt|tests?\b|fehler (find|beheb)|bug|software|website|webseite', r'veröffentlich|deploy|hosting',
     ['inspect_project', 'read_file', 'replace_in_file', 'write_file', 'run_tests', 'run_command'],
     'Softwareprojekte untersuchen, Code schreiben und ändern, Tests ausführen und Fehler beheben (auch Webseiten als HTML/CSS-Dateien).'),
    (r'rechn|berechn|prozent', None, ['calculate'], 'Exakt rechnen.'),
    (r'bildschirm|screenshot|bild analys|foto analys', None, ['take_screenshot', 'analyze_screen', 'analyze_image'],
     'Bildschirm und Bilder analysieren – sofern ein lokales Bildmodell installiert ist (sonst sage ich das).'),
    (r'kalender|termin|erinnerung|e-?mail|mail|nachricht', None, [],
     'Kalender, Erinnerungen und Mail über die ATLAS-App – soweit die Konten verbunden und von macOS freigegeben sind.'),
]


def existing(request: str, tools: dict) -> str | None:
    """Beschreibung, falls die gewünschte Fähigkeit vorhanden ist; sonst None."""
    text = request.lower()
    found = []
    for subject, missing, names, description in CAPABILITIES:
        if not re.search(subject, text):
            continue
        if missing and re.search(missing, text):
            return None                      # genau diese Tätigkeit fehlt → lernen
        if names and not all(name in tools for name in names[:1]):
            continue
        found.append(description)
    if not found:
        return None
    return 'Das kann ich bereits: ' + ' '.join(dict.fromkeys(found)) + ' Sag mir einfach, was ich konkret tun soll.'
