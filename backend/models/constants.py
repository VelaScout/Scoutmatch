"""Gemeinsame Wertebereiche (Enums), die von mehreren Routen/Services genutzt
werden. SQLite validiert dieselben Werte zusätzlich über CHECK-Constraints in
schema.sql – diese Konstanten sind die serverseitige Entsprechung davon."""

VERIFICATION_TYPES = ("identitaet", "vereinszugehoerigkeit", "leistungsdaten")

VERIFICATION_STATUSES = ("selbst_angegeben", "pruefung_ausstehend", "verifiziert", "abgelehnt")

CLUB_STATUSES = ("pending", "verified", "rejected")

CONTACT_REQUEST_STATUSES = ("pending", "accepted", "declined")

PLAYER_PUBLIC_FIELDS = (
    "id, vorname, nachname, geburtsdatum, wohnort, nationalitaet, hauptposition, "
    "nebenposition, aktueller_verein, liga, groesse, gewicht, starker_fuss, "
    "vertragsstatus, vertragsende, verfuegbar_ab, wechselstatus, profilbild, is_demo"
)
