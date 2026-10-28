#!/usr/bin/env python3
"""Kostenloser, kontrollierter Themenplan für ATLAS 0.8.

Legt nur bestehende topic-Jobs an; keine Webanfragen beim Import.
Standard: Vorschau. Kein Einschalten der laufenden Lernzyklen.
"""
from __future__ import annotations
import argparse
import json
import os
import sqlite3
import sys
from pathlib import Path
from datetime import datetime, timezone

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


def connect(db_path: Path):
    db_path.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(str(db_path), timeout=15)
    con.execute('PRAGMA busy_timeout=15000')
    con.execute('''CREATE TABLE IF NOT EXISTS evolution_jobs (
        id INTEGER PRIMARY KEY, kind TEXT NOT NULL, payload TEXT NOT NULL, origin TEXT NOT NULL,
        status TEXT NOT NULL, created_at TEXT NOT NULL, started_at TEXT, finished_at TEXT,
        seconds REAL NOT NULL DEFAULT 0, result TEXT NOT NULL DEFAULT '')''')
    return con


def queue(db_path: Path, packages: list[str]) -> tuple[int, int]:
    added = existing = 0
    with connect(db_path) as db:
        # Repariert ältere fehlerhafte Wissenspaket-Imports: Der Scheduler kennt nur 'topic'.
        old_jobs = db.execute("SELECT id, payload FROM evolution_jobs WHERE kind='learn_topic' AND origin='wissenspaket' AND status='wartet'").fetchall()
        for job_id, payload in old_jobs:
            duplicate = db.execute("SELECT 1 FROM evolution_jobs WHERE kind='topic' AND payload=? AND status IN ('wartet','läuft','fertig')", (payload,)).fetchone()
            if duplicate:
                db.execute("UPDATE evolution_jobs SET status='abgebrochen', result='Duplikat aus alter Wissenspaket-Version' WHERE id=?", (job_id,))
            else:
                db.execute("UPDATE evolution_jobs SET kind='topic' WHERE id=?", (job_id,))
        for key in packages:
            for topic in PACKAGES[key]:
                payload = json.dumps({'topic': topic}, ensure_ascii=False, sort_keys=True)
                old = db.execute('SELECT 1 FROM evolution_jobs WHERE kind=? AND payload=? AND status IN (\'wartet\',\'läuft\',\'fertig\')', ('topic', payload)).fetchone()
                if old:
                    existing += 1
                    continue
                db.execute('INSERT INTO evolution_jobs(kind,payload,origin,status,created_at) VALUES (?,?,?,?,?)',
                           ('topic', payload, 'wissenspaket', 'wartet', datetime.now(timezone.utc).isoformat()))
                added += 1
    return added, existing


def main(argv=None):
    p = argparse.ArgumentParser(description='ATLAS Wissenspakete (standardmäßig nur Vorschau)')
    p.add_argument('--pakete', nargs='+', default=['alle'], choices=['alle', *PACKAGES])
    p.add_argument('--einreihen', action='store_true', help='Aufträge explizit in die ATLAS-Datenbank schreiben')
    p.add_argument('--datenbank', type=Path, default=Path(os.environ.get('ATLAS_DATA_DIR', str(Path.home()/'.atlas-ai'))) / 'atlas.db')
    args = p.parse_args(argv)
    selected = list(PACKAGES) if 'alle' in args.pakete else list(dict.fromkeys(args.pakete))
    print('Datenbank:', args.datenbank.expanduser())
    print('Pakete:', ', '.join(selected))
    print('Themen insgesamt:', sum(len(PACKAGES[name]) for name in selected))
    print('Kosten: keine API-Gebühren; Internet/Hardware-Strombedarf möglich.')
    print('Hinweis: Einzelne Themen erschließen nicht das gesamte Wissen eines Fachgebietes.')
    if not args.einreihen:
        print('NUR VORSCHAU. Zum Einreihen --einreihen hinzufügen. Lernzyklen werden NICHT aktiviert.')
        return 0
    if args.datenbank.exists() and args.datenbank.is_dir():
        p.error('Datenbankpfad ist ein Verzeichnis.')
    added, existing = queue(args.datenbank.expanduser(), selected)
    print(f'In die Warteschlange aufgenommen: {added}; bereits vorhanden: {existing}.')
    print('Zum Ausführen: ATLAS starten und in Learning & Evolution die Lernfunktion aktivieren.')
    return 0

if __name__ == '__main__':
    sys.exit(main())
