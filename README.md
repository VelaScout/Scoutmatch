# ScoutMatch – lokales Entwicklungs-Setup

ScoutMatch verbindet Fußballspieler und Vereine: Spieler legen ein Profil an,
Vereine (nach Freigabe durch einen Admin) durchsuchen den Spielerpool und
nehmen Kontakt auf. Diese Anleitung richtet sich an jemanden **ohne
Entwicklererfahrung** und führt Schritt für Schritt durch die lokale
Einrichtung.

> **Wichtiger Hinweis zur Datenbank:** Dieses Projekt läuft mit **SQLite**
> (eine einzelne Datei unter `instance/scoutmatch.db`) – nicht mit
> PostgreSQL/Supabase. Das war eine bewusste Entscheidung für den MVP:
> kostenlos, keine externen Zugangsdaten, funktioniert sofort nach dem
> Herunterladen. Es ist **kein Supabase-Konto** und **keine Internetverbindung**
> zur Datenbank nötig. Ein späterer Umstieg auf PostgreSQL/Supabase ist möglich,
> ist aber ein separates, größeres Vorhaben (eigener Auftrag, eigene Kosten-
> und Aufwandsabwägung) und nicht Teil dieses Setups.

---

## 1. Benötigte Software

| Software | Warum | Wo bekommen |
|---|---|---|
| **Python 3.9 oder neuer** | Backend (Flask) | [python.org/downloads](https://www.python.org/downloads/) |
| Ein Terminal | Befehle ausführen | macOS: "Terminal"-App, Windows: PowerShell |
| Ein Webbrowser | Website ansehen | Chrome, Firefox, Safari, … |

Ob Python installiert ist, prüfst du mit:

```bash
python3 --version
```

Es sollte etwas wie `Python 3.9.x` oder höher erscheinen.

---

## 2. Projekt herunterladen / öffnen

Öffne ein Terminal und wechsle in den Projektordner (falls du nicht schon
darin bist):

```bash
cd /Users/velasco/scoutmatch
```

---

## 3. Projektstruktur (zur Orientierung)

```
scoutmatch/
├── app.py                  Einstiegspunkt: startet den Server
├── config.py                Konfiguration (liest .env)
├── requirements.txt          Liste der Python-Pakete
├── .env                       Deine lokalen Zugangsdaten/Einstellungen (nicht in Git!)
├── .env.example                Vorlage für .env
├── seed.py                     Legt Demo-Spieler + Demo-Verein an
├── create_admin.py              Legt ein Admin-Konto an
├── backend/                    Die eigentliche Anwendungslogik
│   ├── database/                Datenbankverbindung + Schema (schema.sql)
│   ├── models/                    Gemeinsame Datenstrukturen/Konstanten
│   ├── routes/                     Ein Modul pro Funktionsbereich (Auth, Spieler, Admin, …)
│   ├── services/                    Mailer (Dev-Postausgang), Audit-Log
│   └── utils/                        Sicherheits-Helfer (CSRF, Rollen-Check, Validierung)
├── tests/                       Automatisierte Tests (pytest)
├── public/                      Die Website selbst (HTML/CSS/JS) – unverändert
├── uploads/                     Hochgeladene Profilbilder
└── instance/                    Die SQLite-Datenbankdatei + Sessions
```

---

## 4. Virtuelle Umgebung erstellen

Eine virtuelle Umgebung hält die Python-Pakete dieses Projekts von anderen
Projekten auf deinem Rechner getrennt.

```bash
cd /Users/velasco/scoutmatch
python3 -m venv venv
source venv/bin/activate
```

Falls du Windows benutzt, lautet der letzte Befehl stattdessen:
`venv\Scripts\activate`

Dein Terminal zeigt danach `(venv)` am Zeilenanfang – das bedeutet, es
funktioniert.

> Diese venv existiert im Projekt bereits (Ordner `venv/`). Du musst obige
> Schritte nur wiederholen, falls du komplett neu startest.

---

## 5. Dependencies (Pakete) installieren

```bash
pip install -r requirements.txt
```

Das installiert Flask, Flask-Session, Flask-Limiter, bcrypt, python-dotenv
und pytest.

---

## 6. `.env`-Datei erstellen

```bash
cp .env.example .env
```

Erzeuge dir einen zufälligen, langen `SECRET_KEY`:

```bash
python3 -c "import secrets; print(secrets.token_hex(32))"
```

Öffne `.env` in einem Texteditor und trage den erzeugten Wert bei
`SECRET_KEY=` ein.

### Bedeutung jeder `.env`-Variable

| Variable | Bedeutung | Beispiel/Standard |
|---|---|---|
| `SECRET_KEY` | Geheimer Schlüssel für Sessions/Signaturen. Muss zufällig und lang sein. **Niemals** öffentlich teilen. | zufälliger 64-stelliger Hex-String |
| `FLASK_ENV` | Kennzeichnet die Umgebung als Entwicklung. | `development` |
| `PORT` | Port, auf dem der lokale Server läuft. | `5001` |
| `DATABASE_PATH` | Pfad zur SQLite-Datenbankdatei (relativ zum Projektordner). | `instance/scoutmatch.db` |
| `MAX_UPLOAD_BYTES` | Maximale Dateigröße für Profilbild-Uploads in Bytes. | `5242880` (5 MB) |
| `SESSION_COOKIE_SECURE` | Ob das Session-Cookie nur über HTTPS gesendet werden darf. Lokal `false`, in echtem Betrieb **muss** dies `true` sein (siehe "Production Deployment"). | `false` |

Es gibt **keine** Supabase-/Datenbank-Zugangsdaten einzutragen – SQLite
braucht keinen externen Dienst.

---

## 7. Datenbankschema anlegen (passiert automatisch)

Du musst nichts manuell ausführen: Beim ersten Start des Servers (Schritt 9)
legt `backend/database/connection.py` automatisch alle benötigten Tabellen in
`instance/scoutmatch.db` an (siehe `backend/database/schema.sql`). Bereits
vorhandene Daten aus einer älteren Version des Schemas werden dabei
migriert (z. B. Tabellenumbenennungen), ohne dass etwas verloren geht.

---

## 8. (Optional) Demo-Daten anlegen

Für zum Ausprobieren vorbereitete Demo-Spieler und einen Demo-Verein:

```bash
python3 seed.py
```

Das legt u. a. an:
- `spieler1@test.scoutmatch.local` bis `spieler8@test.scoutmatch.local` (Passwort jeweils `Test1234!`)
- `verein@test.scoutmatch.local` (Passwort `Test1234!`, bereits als Verein freigegeben)

Diese Demo-Spieler sind im Vereins-Dashboard deutlich mit einem
"Demo"-Badge gekennzeichnet.

---

## 9. Entwicklungsserver starten

```bash
python3 app.py
```

Im Terminal erscheint:

```
ScoutMatch läuft lokal auf: http://127.0.0.1:5001
```

Lass dieses Terminal-Fenster offen, solange du die Website benutzen willst.
Zum Beenden: `Strg + C`.

---

## 10. Website öffnen

Öffne im Browser: **http://127.0.0.1:5001**

---

## 11. Testspieler registrieren

1. Klicke auf "Registrieren" → "Ich bin Spieler"
2. Fülle das Formular aus (E-Mail, Passwort, Name, …) und sende es ab
3. Du wirst automatisch eingeloggt und zu deinem Spielerbereich weitergeleitet

---

## 12. E-Mail-Verifizierung testen

Es ist **kein echter E-Mail-Versand** angebunden (siehe unten,
"Production Deployment"). Stattdessen:

1. Logge dich als Admin ein (siehe Schritt 16) und öffne den Tab **"Postausgang"**
   im Admin-Bereich (`admin.html`) – dort erscheint die "gesendete"
   Bestätigungs-E-Mail mit dem Link
2. Alternativ: Der Link wird auch direkt im Terminal ausgegeben, in dem
   `python3 app.py` läuft (Zeile beginnend mit `[MOCK-MAILER]`)
3. Öffne den Link (Format `http://127.0.0.1:5001/e-mail-bestaetigen.html?token=...`)
   – die E-Mail-Adresse gilt danach als bestätigt

---

## 13. Login testen

Logge dich mit den gerade erstellten Zugangsdaten auf `login.html` ein.

---

## 14. Spielerprofil speichern

Im Spielerbereich auf **"Profil bearbeiten"** klicken, Angaben ausfüllen
(Position, Verein, Liga, Statistiken, Videos, …) und speichern. Lade die
Seite neu – die Änderungen bleiben erhalten (in der Datenbank gespeichert).

---

## 15. Testverein registrieren

Wie Schritt 11, aber "Ich vertrete einen Verein" wählen. Der neue
Vereinsaccount hat zunächst den Status **"Verifizierung ausstehend"** und
kann noch **nicht** die Spielersuche nutzen (das ist Absicht, siehe Schritt
16).

---

## 16. Verein als Admin freigeben

Zuerst brauchst du ein Admin-Konto:

```bash
python3 create_admin.py
```

Das legt (ohne Argumente) `admin@test.scoutmatch.local` / `Test1234!` an.
Eigene Zugangsdaten:

```bash
python3 create_admin.py deine@email.de DeinPasswort123
```

Dann:

1. Logge dich mit dem Admin-Konto auf `login.html` ein → du landest in `admin.html`
2. Tab **"Vereine"** öffnen
3. Bei deinem Testverein den Status auf **"Verifiziert"** stellen

---

## 17. Spielersuche testen

Logge dich mit dem freigegebenen Vereinskonto ein → `vereins-dashboard.html`.
Ohne Freigabe würde die Suche mit einer Fehlermeldung abgelehnt (das kannst
du mit einem zweiten, noch nicht freigegebenen Testverein ausprobieren).

---

## 18. Favoriten testen

Im Vereins-Dashboard bei einem Spieler auf das Herz-Symbol klicken → er
erscheint danach unter "Favoriten" (Link oben in der Navigation).

---

## 19. Kontaktanfrage testen

1. Als Verein: Spielerprofil öffnen → "Kontakt anfragen"
2. Als der betroffene Spieler einloggen: Im Spielerbereich unter
   "Kontaktanfragen von Vereinen" erscheint die Anfrage → annehmen oder ablehnen
3. Erst nach Annahme sieht der Verein die (sonst verborgene) Kontakt-E-Mail des Spielers

---

## 20. Passwort-Reset testen

1. Auf `login.html` → "Passwort vergessen?"
2. E-Mail-Adresse eingeben
3. Link im Admin-Postausgang bzw. Terminal-Log suchen (wie Schritt 12)
4. Link öffnen, neues Passwort vergeben

---

## 21. Kontaktformular testen

Auf `kontakt.html` eine Nachricht absenden. Sie wird in der Datenbank
gespeichert (Tabelle `contact_messages`) und zusätzlich als Eintrag im
Admin-Postausgang sichtbar.

---

## 22. Admin-Postausgang prüfen

Admin-Bereich → Tab **"Postausgang"**: zeigt alle "versendeten" E-Mails
(Verifizierung, Passwort-Reset, Kontaktformular-Benachrichtigung) mit
Empfänger, Betreff und vollständigem Text.

---

## 23. Automatisierte Tests ausführen

```bash
python3 -m pytest
```

Alle Tests laufen gegen eine **temporäre, isolierte** Test-Datenbank – deine
echte `instance/scoutmatch.db` wird dabei nicht verändert und es bleiben
keine Testnutzer darin zurück.

---

## Datenbank-Tabellen (Übersicht)

| Tabelle | Inhalt |
|---|---|
| `users` | Zugangsdaten, Rolle, Status aller Konten |
| `player_profiles` | Spielerprofile |
| `club_profiles` | Vereinsprofile |
| `player_stats` | Leistungsdaten je Saison |
| `player_videos` | Video-Links der Spieler |
| `favorites` | Merklisten der Vereine |
| `contact_requests` | Kontaktanfragen Verein → Spieler |
| `verifications` | Verifizierungsstatus (Identität/Verein/Leistung) je Spieler |
| `contact_messages` | Nachrichten aus dem öffentlichen Kontaktformular |
| `email_outbox` | Lokaler Mock-Postausgang aller "gesendeten" E-Mails |
| `admin_audit_log` | Protokoll sicherheitsrelevanter Admin-Aktionen |
| `email_verification_tokens` / `password_reset_tokens` | Einmal verwendbare, zeitlich begrenzte Tokens |

---

## Production Deployment

Dieses Setup ist ausdrücklich **nur für lokale Entwicklung**. Vor einer
echten Veröffentlichung müssen mindestens folgende Punkte angegangen werden:

- **`DEBUG=False`**: In `config.py`/`.env` `FLASK_DEBUG=false` setzen. Der
  eingebaute Flask-Entwicklungsserver (`app.run(...)`) darf grundsätzlich
  nicht produktiv laufen – stattdessen einen echten WSGI-Server verwenden
  (z. B. Gunicorn oder uWSGI) hinter einem Reverse Proxy (nginx/Caddy).
- **Sichere Secret Keys**: `SECRET_KEY` muss ein langer, zufälliger,
  ausschließlich für die Produktivumgebung generierter Wert sein – niemals
  der lokale Entwicklungswert.
- **HTTPS**: Die Seite muss ausschließlich über `https://` erreichbar sein
  (z. B. via Let's Encrypt/Caddy).
- **Secure Cookies**: `SESSION_COOKIE_SECURE=true` setzen, sobald HTTPS
  aktiv ist (sonst werden Session-Cookies über unverschlüsselte
  Verbindungen mitgesendet).
- **Echte E-Mail-Anbindung**: `backend/services/mailer.py` müsste durch
  einen echten Versand ersetzt werden (z. B. über Resend, Brevo oder einen
  SMTP-Anbieter) statt in `email_outbox` zu schreiben. API-Keys dafür
  ausschließlich über Umgebungsvariablen/Secret-Management, nie im Code.
- **Datenbank-Backups**: Bei SQLite genügt ein regelmäßiges Kopieren von
  `instance/scoutmatch.db` (z. B. täglich, versioniert, an einen anderen Ort).
  Bei größerem Nutzerkreis wäre ein Umstieg auf einen verwalteten
  PostgreSQL-Dienst (z. B. Supabase) mit dessen eingebauten Backups sinnvoll
  – das ist dann ein eigenes, separates Migrationsvorhaben.
- **Rate Limiting**: Aktuell nutzt Flask-Limiter In-Memory-Storage (pro
  Prozess). Bei mehreren Server-Prozessen/Instanzen müsste ein gemeinsamer
  Storage-Backend (z. B. Redis) konfiguriert werden, sonst greifen die
  Limits pro Prozess statt global.
- **Uploads**: `uploads/` müsste bei mehreren Server-Instanzen auf einen
  gemeinsamen Speicher (z. B. S3-kompatiblen Object Storage) statt auf die
  lokale Festplatte zeigen.
- **Rechtliches**: Impressum, Datenschutzerklärung und Nutzungsbedingungen
  enthalten aktuell bewusst `[PLATZHALTER]` – diese müssen vor Live-Gang durch
  echte, rechtlich geprüfte Angaben ersetzt werden.
