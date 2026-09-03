"""Lokales Test-Seeding: befüllt die SQLite-Datenbank mit Beispiel-Spielern
und einem Test-Vereinskonto, damit sich Suche/Filter/Favoriten im
Vereins-Dashboard lokal sinnvoll testen lassen.

Nur für die lokale Entwicklungsumgebung gedacht. Nicht bei jedem Serverstart
automatisch ausgeführt – bewusst als separates Skript, einmalig manuell mit:

    source venv/bin/activate
    python3 seed.py

Erzeugt u. a. das Test-Vereinskonto verein@test.scoutmatch.local /
Test1234! (verification_status wird für den Test direkt auf 'verified'
gesetzt, damit das Dashboard sofort nutzbar ist).
"""
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

import bcrypt

BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "instance" / "scoutmatch.db"

PLAYERS = [
    dict(vorname='Max', nachname='Mustermann', geburtsdatum='2004-03-11', groesse=179, gewicht=74,
         starker_fuss='Links', hauptposition='Linksaußen', nebenposition='Offensives Mittelfeld',
         aktueller_verein='FC Beispiel', liga='Oberliga Hamburg', wohnort='Hamburg', nationalitaet='Deutsch',
         vertragsstatus='Vertragslos', vertragsende=None, verfuegbar_ab='Sommer', wechselstatus='Wechsel möglich',
         stats=dict(saison='2025/26', einsaetze=18, startelf=16, minuten=1420, tore=7, assists=6)),
    dict(vorname='Jonas', nachname='Brandt', geburtsdatum='2000-01-05', groesse=190, gewicht=86,
         starker_fuss='Rechts', hauptposition='Torwart', nebenposition=None,
         aktueller_verein='SV Nordstadt', liga='Regionalliga Nord', wohnort='Kiel', nationalitaet='Deutsch',
         vertragsstatus='Unter Vertrag', vertragsende='2027-06-30', verfuegbar_ab='Sommer', wechselstatus='Nur bei Angebot',
         stats=dict(saison='2025/26', einsaetze=24, startelf=24, minuten=2160, tore=0, assists=0)),
    dict(vorname='Elias', nachname='Koch', geburtsdatum='2006-08-22', groesse=184, gewicht=78,
         starker_fuss='Rechts', hauptposition='Innenverteidiger', nebenposition='Rechtsverteidiger',
         aktueller_verein='TSV Waldkamp', liga='Landesliga Bremen', wohnort='Bremen', nationalitaet='Deutsch',
         vertragsstatus='Vertrag läuft aus', vertragsende='2026-06-30', verfuegbar_ab='Sommer', wechselstatus='Wechsel möglich',
         stats=dict(saison='2025/26', einsaetze=21, startelf=20, minuten=1890, tore=2, assists=1)),
    dict(vorname='Til', nachname='Reimers', geburtsdatum='2002-11-02', groesse=176, gewicht=71,
         starker_fuss='Beidfüßig', hauptposition='Zentrales Mittelfeld', nebenposition='Defensives Mittelfeld',
         aktueller_verein='FC Hansa Amateure', liga='Oberliga Niedersachsen', wohnort='Hannover', nationalitaet='Deutsch',
         vertragsstatus='Wechsel möglich', vertragsende=None, verfuegbar_ab='Winter', wechselstatus='Wechsel möglich',
         stats=dict(saison='2025/26', einsaetze=19, startelf=17, minuten=1610, tore=4, assists=9)),
    dict(vorname='Noah', nachname='Petersen', geburtsdatum='2007-04-14', groesse=181, gewicht=73,
         starker_fuss='Rechts', hauptposition='Rechtsaußen', nebenposition='Stürmer',
         aktueller_verein='VfB Küstenstadt', liga='Verbandsliga Schleswig-Holstein', wohnort='Flensburg', nationalitaet='Deutsch',
         vertragsstatus='Vertragslos', vertragsende=None, verfuegbar_ab='Sommer', wechselstatus='Wechsel möglich',
         stats=dict(saison='2025/26', einsaetze=15, startelf=12, minuten=1180, tore=5, assists=3)),
    dict(vorname='Finn', nachname='Albrecht', geburtsdatum='1997-09-30', groesse=178, gewicht=76,
         starker_fuss='Links', hauptposition='Linksverteidiger', nebenposition=None,
         aktueller_verein='SC Rotweiß', liga='Regionalliga Nord', wohnort='Rostock', nationalitaet='Deutsch',
         vertragsstatus='Unter Vertrag', vertragsende='2026-06-30', verfuegbar_ab='Sommer', wechselstatus='Kein Wechsel geplant',
         stats=dict(saison='2025/26', einsaetze=22, startelf=22, minuten=1980, tore=1, assists=5)),
    dict(vorname='Leon', nachname='Wagner', geburtsdatum='2003-02-18', groesse=186, gewicht=80,
         starker_fuss='Rechts', hauptposition='Stürmer', nebenposition='Rechtsaußen',
         aktueller_verein='TuS Eichenfeld', liga='Oberliga Hamburg', wohnort='Hamburg', nationalitaet='Deutsch',
         vertragsstatus='Vertrag läuft aus', vertragsende='2026-06-30', verfuegbar_ab='Winter', wechselstatus='Wechsel möglich',
         stats=dict(saison='2025/26', einsaetze=20, startelf=19, minuten=1720, tore=14, assists=4)),
    dict(vorname='David', nachname='Sörensen', geburtsdatum='2001-06-09', groesse=182, gewicht=77,
         starker_fuss='Beidfüßig', hauptposition='Offensives Mittelfeld', nebenposition='Zentrales Mittelfeld',
         aktueller_verein='FC Alsterblick', liga='Landesliga Bremen', wohnort='Bremen', nationalitaet='Deutsch',
         vertragsstatus='Wechsel möglich', vertragsende=None, verfuegbar_ab='Winter', wechselstatus='Wechsel möglich',
         stats=dict(saison='2025/26', einsaetze=17, startelf=15, minuten=1390, tore=6, assists=8)),
]

# Ein paar Beispiel-Videolinks für die ersten Demo-Spieler, damit sich die
# Video-Funktion (Profil & Suche) lokal ohne eigenen Upload testen lässt.
DEMO_VIDEOS = {
    1: [("Saisonrückblick 2025/26", "https://www.youtube.com/watch?v=dQw4w9WgXcQ")],
    4: [("Tore & Vorlagen – Highlights", "https://www.youtube.com/watch?v=dQw4w9WgXcQ")],
    7: [("Scouting-Zusammenschnitt", "https://www.youtube.com/watch?v=dQw4w9WgXcQ")],
}


def _now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _hash(password):
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def main():
    if not DB_PATH.exists():
        raise SystemExit(
            "Datenbank nicht gefunden unter " + str(DB_PATH) +
            ". Bitte zuerst den Server einmal starten (python3 app.py), damit das Schema angelegt wird."
        )

    db = sqlite3.connect(str(DB_PATH))
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys = ON")
    now = _now()

    for i, p in enumerate(PLAYERS, start=1):
        email = f"spieler{i}@test.scoutmatch.local"
        existing = db.execute("SELECT id FROM users WHERE email = ?", (email,)).fetchone()
        if existing:
            continue

        cur = db.execute(
            "INSERT INTO users (email, password_hash, role, email_verified, created_at, updated_at) "
            "VALUES (?, ?, 'player', 1, ?, ?)",
            (email, _hash("Test1234!"), now, now),
        )
        user_id = cur.lastrowid

        cur = db.execute(
            """INSERT INTO player_profiles (
                user_id, vorname, nachname, geburtsdatum, wohnort, nationalitaet,
                hauptposition, nebenposition, aktueller_verein, liga, groesse, gewicht,
                starker_fuss, vertragsstatus, vertragsende, verfuegbar_ab, wechselstatus,
                profil_sichtbar, is_demo, created_at, updated_at
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,1,1,?,?)""",
            (
                user_id, p['vorname'], p['nachname'], p['geburtsdatum'], p['wohnort'], p['nationalitaet'],
                p['hauptposition'], p['nebenposition'], p['aktueller_verein'], p['liga'], p['groesse'], p['gewicht'],
                p['starker_fuss'], p['vertragsstatus'], p['vertragsende'], p['verfuegbar_ab'], p['wechselstatus'],
                now, now,
            ),
        )
        player_id = cur.lastrowid

        for titel, video_url in DEMO_VIDEOS.get(i, []):
            db.execute(
                "INSERT INTO player_videos (player_id, titel, video_url) VALUES (?, ?, ?)",
                (player_id, titel, video_url),
            )

        s = p['stats']
        db.execute(
            "INSERT INTO player_stats (player_id, saison, einsaetze, startelf, minuten, tore, assists, verification_status) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, 'verifiziert')",
            (player_id, s['saison'], s['einsaetze'], s['startelf'], s['minuten'], s['tore'], s['assists']),
        )

        for vtype in ("identitaet", "vereinszugehoerigkeit", "leistungsdaten"):
            db.execute(
                "INSERT INTO verifications (user_id, verification_type, status) VALUES (?, ?, 'verifiziert')",
                (user_id, vtype),
            )

        print(f"Spieler angelegt: {email} (Passwort: Test1234!)")

    club_email = "verein@test.scoutmatch.local"
    existing_club = db.execute("SELECT id FROM users WHERE email = ?", (club_email,)).fetchone()
    if not existing_club:
        cur = db.execute(
            "INSERT INTO users (email, password_hash, role, email_verified, created_at, updated_at) "
            "VALUES (?, ?, 'club', 1, ?, ?)",
            (club_email, _hash("Test1234!"), now, now),
        )
        club_user_id = cur.lastrowid
        db.execute(
            """INSERT INTO club_profiles (
                user_id, vereinsname, liga, ort, website,
                ansprechpartner_vorname, ansprechpartner_nachname, funktion,
                verification_status, created_at, updated_at
            ) VALUES (?,?,?,?,?,?,?,?, 'verified', ?, ?)""",
            (club_user_id, "Testverein Hamburg e.V.", "Oberliga Hamburg", "Hamburg", "https://example.com",
             "Anna", "Testleiter", "Sportlicher Leiter", now, now),
        )
        print(f"Vereinskonto angelegt: {club_email} (Passwort: Test1234!, Status: verified)")

    db.commit()
    db.close()
    print("\nFertig. Zum Testen: Server starten (python3 app.py) und mit den oben genannten Zugangsdaten einloggen.")


if __name__ == "__main__":
    main()
