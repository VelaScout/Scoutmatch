"""Wissenspakete: vorbereitete Themenlisten für den Wissensaufbau (Learning & Evolution).

Übernommen aus Ihrem Paket ATLAS-Local-0.8.0_2 und angebunden:
- Einreihen nur auf ausdrücklichen Wunsch (App, Befehl oder Sprache); Vorschau ist der Standard.
- Die Aufträge laufen nur, wenn die Lernzyklen in „Learning & Evolution“ eingeschaltet sind, im Tageslimit
  für Rechenzeit, mit Internet nur wenn erlaubt, und pausierbar. Nichts startet von selbst.
- Jedes Thema nutzt den vorhandenen Wissensaufbau (knowledge.py): Quellen lesen, Aussagen gegen den
  Quelltext prüfen, mit Quelle und Datum speichern. Es werden keine Modellgewichte verändert.
- Kosten: keine API-Gebühren (lokales Modell, frei zugängliche Webseiten).

Aufruf: python3 -m atlas.wissenspakete [--pakete …] [--einreihen]
"""
from __future__ import annotations

import argparse
import contextlib
import os
import sqlite3
import sys
from pathlib import Path

ORIGIN = 'wissenspaket'

PACKAGES = {
    'geschichte': ['Frühgeschichte und Entstehung der Landwirtschaft','Antike Hochkulturen und Quellenkritik','Antikes Griechenland','Römisches Reich','Weltreligionen in der Geschichte','Mittelalter in Europa, Asien und Afrika','Kolonialismus und seine Folgen','Renaissance und Reformation','Aufklärung','Industrialisierung','Erster Weltkrieg','Zweiter Weltkrieg und Holocaust','Kalter Krieg','Dekolonisation','Weltgeschichte seit 1990'],
    'physik': ['Wissenschaftliche Methode und Messfehler','Mechanik und Newtonsche Gesetze','Energie und Erhaltungssätze','Schwingungen und Wellen','Thermodynamik','Elektrizität und Stromkreise','Magnetismus und Induktion','Optik','Elektromagnetische Wellen','Relativitätstheorie','Quantenmechanik Grundlagen','Atom- und Kernphysik','Teilchenphysik','Astrophysik','Kosmologie'],
    'mathematik': ['Arithmetik und Zahlentheorie','Algebra','Funktionen und Graphen','Geometrie','Trigonometrie','Differentialrechnung','Integralrechnung','Lineare Algebra','Wahrscheinlichkeit','Statistik und Kausalität','Diskrete Mathematik','Optimierung','Numerische Methoden','Logik und Beweise'],
    'chemie': ['Atombau und Periodensystem','Chemische Bindungen','Stöchiometrie','Chemisches Gleichgewicht','Säuren und Basen','Redoxreaktionen','Organische Chemie','Biochemie Grundlagen','Materialwissenschaften','Elektrochemie','Umweltchemie','Analytische Chemie'],
    'biologie': ['Evolution und natürliche Selektion','Genetik und DNA','Molekularbiologie','Zellbiologie','Mikrobiologie','Ökologie','Pflanzenbiologie','Tierphysiologie','Menschliche Anatomie','Immunologie','Neurowissenschaften','Epidemiologie Grundlagen'],
    'geographie': ['Kontinente Länder und Ozeane','Plattentektonik','Klimasysteme','Wetter und Meteorologie','Meereskunde','Ökosysteme der Erde','Demographie','Urbanisierung','Migration','Rohstoffe und Energieträger','Globale Lieferketten','Geopolitische Regionen'],
    'informatik': ['Computerarchitektur','Betriebssysteme','Netzwerke und Internetprotokolle','Algorithmen und Datenstrukturen','Datenbanken','Softwaretechnik und Tests','Python Programmierung','Webentwicklung','Informationssicherheit','Kryptografie Grundlagen','Machine Learning','Large Language Models','Retrieval-Augmented Generation','KI-Agenten und Tool Calling','Datenschutz und KI-Ethik'],
    'wirtschaft': ['Volkswirtschaft Grundlagen','Angebot Nachfrage und Märkte','Makroökonomie','Inflation und Geldpolitik','Öffentliche Finanzen','Unternehmensführung','Buchhaltung und Bilanzierung','Investitionen und Kapitalwert','Unternehmensbewertung','Banken und Finanzsystem','Risikomanagement','Internationaler Handel','Behavioral Economics','Unternehmensstrategie'],
    'politik_recht': ['Demokratie und politische Systeme','Deutsches Grundgesetz','EU Institutionen und Gesetzgebung','Vereinte Nationen','Internationales Recht Grundlagen','Menschenrechte','Rechtsstaat und Gewaltenteilung','Zivilrecht Grundlagen','Strafrecht Grundlagen','Arbeitsrecht Grundlagen','Datenschutzrecht','Politische Ideengeschichte'],
    'philosophie': ['Antike Philosophie','Logik und Argumentationsfehler','Erkenntnistheorie','Ethik','Platon und Aristoteles','Descartes und Rationalismus','Empirismus','Immanuel Kant','Utilitarismus und Bentham','Politische Philosophie','Wissenschaftsphilosophie','Philosophie des Geistes'],
    'psychologie': ['Wissenschaftliche Psychologie','Kognitive Psychologie','Lernen und Gedächtnis','Aufmerksamkeit und Wahrnehmung','Entwicklungspsychologie','Sozialpsychologie','Persönlichkeit','Motivation','Emotionen','Entscheidungspsychologie','Psychische Gesundheit Grundlagen','Forschungsmethoden in der Psychologie'],
    'medizin': ['Evidenzbasierte Medizin','Anatomie und Physiologie','Herz-Kreislauf-System','Atmung','Verdauung und Ernährung','Endokrinologie','Infektionskrankheiten','Impfungen','Prävention und öffentliche Gesundheit','Pharmakologie Grundlagen','Neurologie Grundlagen','Erste Hilfe Grundlagen'],
    'kultur': ['Weltliteratur','Literaturgeschichte','Musiktheorie','Klassische Musikgeschichte','Bildende Kunst','Architekturgeschichte','Filmgeschichte','Sprachwissenschaft','Sprachen und Sprachfamilien','Religionswissenschaft','Medienkompetenz','Kulturwissenschaften'],
    'technik': ['Ingenieurwissenschaftliche Grundlagen','Elektrotechnik','Maschinenbau','Robotik','Sensorik und Messtechnik','Regelungstechnik','Energietechnik','Erneuerbare Energien','Raumfahrttechnik','Fertigung und 3D-Druck','Automatisierung','Technikfolgenabschätzung'],
    'sport': ['Trainingslehre','Sportphysiologie','Biomechanik','Sporternährung','Regeneration und Schlaf','Verletzungsprävention','Fußballtaktik','Fußballanalyse','Sportpsychologie','Leistungsdiagnostik','Sportstatistik','Talententwicklung'],
}


def preview(names: list[str]) -> dict:
    selected = list(PACKAGES) if 'alle' in names else [n for n in dict.fromkeys(names) if n in PACKAGES]
    return {'packages': selected, 'topics': sum(len(PACKAGES[n]) for n in selected)}


def enqueue(scheduler, names: list[str]) -> tuple[int, int]:
    """Reiht die Themen als Lernaufträge ein (Art 'topic'). Bereits wartende, laufende oder fertige Themen
    werden übersprungen. Gibt (neu, schon_vorhanden) zurück."""
    import json
    added = existing = 0
    with scheduler.connect() as db:
        known = {row[0] for row in db.execute(
            "SELECT payload FROM evolution_jobs WHERE kind='topic' AND status IN ('wartet','läuft','fertig')")}
    for name in preview(names)['packages']:
        for topic in PACKAGES[name]:
            if json.dumps({'topic': topic}, ensure_ascii=False, sort_keys=True) in known:
                existing += 1
                continue
            scheduler.submit('topic', {'topic': topic}, origin=ORIGIN)
            added += 1
    return added, existing


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description='ATLAS Wissenspakete (standardmäßig nur Vorschau)')
    parser.add_argument('--pakete', nargs='+', default=['alle'], choices=['alle', *PACKAGES])
    parser.add_argument('--einreihen', action='store_true', help='Aufträge ausdrücklich in die ATLAS-Datenbank schreiben')
    parser.add_argument('--datenbank', type=Path,
                        default=Path(os.environ.get('ATLAS_DATA_DIR', str(Path.home() / '.atlas-ai'))) / 'atlas.db')
    args = parser.parse_args(argv)
    info = preview(args.pakete)
    print('Pakete:', ', '.join(info['packages']))
    print('Themen insgesamt:', info['topics'])
    print('Kosten: keine API-Gebühren; Internetzugriff und Rechenzeit auf dem Mac.')
    print('Hinweis: Einzelne Themen erschließen nicht das gesamte Wissen eines Fachgebiets.')
    if not args.einreihen:
        print('NUR VORSCHAU. Zum Einreihen --einreihen hinzufügen. Lernzyklen werden NICHT eingeschaltet.')
        return 0
    if args.datenbank.is_dir():
        parser.error('Datenbankpfad ist ein Verzeichnis.')
    args.datenbank.parent.mkdir(parents=True, exist_ok=True)

    @contextlib.contextmanager
    def connect():
        db = sqlite3.connect(str(args.datenbank), timeout=15)
        try:
            with db:
                yield db
        finally:
            db.close()
    from .evolution import Scheduler
    scheduler = Scheduler(connect)
    scheduler.register('topic', lambda payload, stop: {})      # nur zum Einreihen; ausgeführt wird im ATLAS-Dienst
    added, existing = enqueue(scheduler, args.pakete)
    print(f'In die Warteschlange aufgenommen: {added}; bereits vorhanden: {existing}.')
    print('Ausgeführt wird erst, wenn in „Learning & Evolution“ die Lernzyklen eingeschaltet sind (mit Tageslimit, pausierbar).')
    return 0


if __name__ == '__main__':
    sys.exit(main())
