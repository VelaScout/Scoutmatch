-- ScoutMatch – lokales Datenbankschema (SQLite)
-- Alle Fremdschlüssel sind aktiv (PRAGMA foreign_keys=ON wird in db.py gesetzt).

CREATE TABLE IF NOT EXISTS users (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  email           TEXT NOT NULL UNIQUE,
  password_hash   TEXT NOT NULL,
  role            TEXT NOT NULL CHECK(role IN ('player','club','admin')),
  email_verified  INTEGER NOT NULL DEFAULT 0,
  is_locked       INTEGER NOT NULL DEFAULT 0,
  last_login_at   TEXT,
  created_at      TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS player_profiles (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id           INTEGER NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  vorname           TEXT,
  nachname          TEXT,
  geburtsdatum      TEXT,
  wohnort           TEXT,
  nationalitaet     TEXT,
  hauptposition     TEXT,
  nebenposition     TEXT,
  aktueller_verein  TEXT,
  liga              TEXT,
  groesse           INTEGER,
  gewicht           INTEGER,
  starker_fuss      TEXT,
  vertragsstatus    TEXT,
  vertragsende      TEXT,
  verfuegbar_ab     TEXT,
  wechselstatus     TEXT,
  profilbild        TEXT,
  profil_sichtbar   INTEGER NOT NULL DEFAULT 1,
  is_demo           INTEGER NOT NULL DEFAULT 0,
  created_at        TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at        TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS player_videos (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  player_id   INTEGER NOT NULL REFERENCES player_profiles(id) ON DELETE CASCADE,
  titel       TEXT NOT NULL,
  video_url   TEXT NOT NULL,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS club_profiles (
  id                        INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id                   INTEGER NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  vereinsname               TEXT,
  liga                      TEXT,
  ort                       TEXT,
  website                   TEXT,
  ansprechpartner_vorname   TEXT,
  ansprechpartner_nachname  TEXT,
  funktion                  TEXT,
  verification_status       TEXT NOT NULL DEFAULT 'pending' CHECK(verification_status IN ('pending','verified','rejected')),
  created_at                TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at                TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS player_stats (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  player_id             INTEGER NOT NULL REFERENCES player_profiles(id) ON DELETE CASCADE,
  saison                TEXT NOT NULL,
  einsaetze             INTEGER NOT NULL DEFAULT 0,
  startelf              INTEGER NOT NULL DEFAULT 0,
  minuten               INTEGER NOT NULL DEFAULT 0,
  tore                  INTEGER NOT NULL DEFAULT 0,
  assists               INTEGER NOT NULL DEFAULT 0,
  verification_status   TEXT NOT NULL DEFAULT 'selbst_angegeben'
                         CHECK(verification_status IN ('selbst_angegeben','pruefung_ausstehend','verifiziert','abgelehnt')),
  UNIQUE(player_id, saison)
);

CREATE TABLE IF NOT EXISTS favorites (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  club_id     INTEGER NOT NULL REFERENCES club_profiles(id) ON DELETE CASCADE,
  player_id   INTEGER NOT NULL REFERENCES player_profiles(id) ON DELETE CASCADE,
  list_name   TEXT NOT NULL DEFAULT 'Favoriten',
  notiz       TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(club_id, player_id, list_name)
);

CREATE TABLE IF NOT EXISTS verifications (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id             INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  verification_type   TEXT NOT NULL CHECK(verification_type IN ('identitaet','vereinszugehoerigkeit','leistungsdaten')),
  status               TEXT NOT NULL DEFAULT 'selbst_angegeben'
                        CHECK(status IN ('selbst_angegeben','pruefung_ausstehend','verifiziert','abgelehnt')),
  reviewed_at          TEXT,
  reviewed_by          INTEGER REFERENCES users(id),
  UNIQUE(user_id, verification_type)
);

CREATE TABLE IF NOT EXISTS contact_requests (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  club_id     INTEGER NOT NULL REFERENCES club_profiles(id) ON DELETE CASCADE,
  player_id   INTEGER NOT NULL REFERENCES player_profiles(id) ON DELETE CASCADE,
  status      TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','accepted','declined')),
  message     TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(club_id, player_id)
);

-- Zeitlich begrenzte, einmal verwendbare Tokens für E-Mail-Verifizierung und
-- Passwort-Reset. Es wird nur der Hash des Tokens gespeichert, nie der Token
-- selbst (analog zu Passwörtern) – ein DB-Leak allein reicht damit nicht aus,
-- um ein Token zu missbrauchen.
CREATE TABLE IF NOT EXISTS email_verification_tokens (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash  TEXT NOT NULL UNIQUE,
  expires_at  TEXT NOT NULL,
  used_at     TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS password_reset_tokens (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash  TEXT NOT NULL UNIQUE,
  expires_at  TEXT NOT NULL,
  used_at     TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Nachrichten aus dem öffentlichen Kontaktformular (kontakt.html). Das
-- Frontend sendet aktuell kein eigenes Betreff-Feld – "subject" ist daher
-- nullable und wird serverseitig mit einem Standardwert befüllt.
CREATE TABLE IF NOT EXISTS contact_messages (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT NOT NULL,
  email       TEXT NOT NULL,
  subject     TEXT,
  message     TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'neu' CHECK(status IN ('neu','gelesen','erledigt')),
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Lokaler Mock-Postausgang (ersetzt die frühere outbox.jsonl-Datei). Jede
-- "gesendete" E-Mail (Verifizierung, Passwort-Reset, ...) landet hier und ist
-- für Admins über GET /api/admin/outbox einsehbar.
CREATE TABLE IF NOT EXISTS email_outbox (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  recipient    TEXT NOT NULL,
  subject      TEXT NOT NULL,
  body         TEXT NOT NULL,
  email_type   TEXT NOT NULL DEFAULT 'sonstiges'
               CHECK(email_type IN ('email_verification','password_reset','sonstiges')),
  status       TEXT NOT NULL DEFAULT 'gesendet' CHECK(status IN ('gesendet','fehlgeschlagen')),
  created_at   TEXT NOT NULL DEFAULT (datetime('now')),
  sent_at      TEXT
);

-- Protokoll sicherheitsrelevanter Admin-Aktionen (Freigaben, Sperren,
-- Verifizierungsentscheidungen, ...). Wird ausschließlich serverseitig
-- geschrieben, nie vom Client.
CREATE TABLE IF NOT EXISTS admin_audit_log (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  admin_user_id  INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  action         TEXT NOT NULL,
  target_type    TEXT NOT NULL,
  target_id      INTEGER NOT NULL,
  details        TEXT,
  created_at     TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_player_profiles_search
  ON player_profiles(hauptposition, liga, wohnort, starker_fuss, wechselstatus);
CREATE INDEX IF NOT EXISTS idx_favorites_club ON favorites(club_id);
CREATE INDEX IF NOT EXISTS idx_player_stats_player ON player_stats(player_id);
CREATE INDEX IF NOT EXISTS idx_contact_requests_club ON contact_requests(club_id);
CREATE INDEX IF NOT EXISTS idx_contact_requests_player ON contact_requests(player_id);
CREATE INDEX IF NOT EXISTS idx_evt_user ON email_verification_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_prt_user ON password_reset_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_player_videos_player ON player_videos(player_id);
CREATE INDEX IF NOT EXISTS idx_email_outbox_created ON email_outbox(created_at);
CREATE INDEX IF NOT EXISTS idx_admin_audit_admin ON admin_audit_log(admin_user_id);
CREATE INDEX IF NOT EXISTS idx_admin_audit_target ON admin_audit_log(target_type, target_id);
