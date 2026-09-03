"""SQLite-Verbindung für ScoutMatch.

Nutzt ausschließlich parametrisierte Queries (nirgends String-Concat mit
Nutzereingaben) – das ist der zentrale Schutz gegen SQL-Injection.
"""
import sqlite3
from pathlib import Path

from flask import current_app, g

# backend/database/connection.py -> backend/database -> backend -> Projektwurzel
PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
SCHEMA_PATH = Path(__file__).resolve().parent / "schema.sql"


def get_db():
    if "db" not in g:
        db_path = PROJECT_ROOT / current_app.config["DATABASE_PATH"]
        db_path.parent.mkdir(parents=True, exist_ok=True)
        g.db = sqlite3.connect(str(db_path))
        g.db.row_factory = sqlite3.Row
        g.db.execute("PRAGMA foreign_keys = ON")
    return g.db


def close_db(_exc=None):
    db = g.pop("db", None)
    if db is not None:
        db.close()


def _table_exists(db, name):
    return db.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name = ?", (name,)
    ).fetchone() is not None


def _rename_table_if_needed(db, old_name, new_name):
    """Benennt eine bereits vorhandene Tabelle in den neuen Namen um, ohne
    Daten zu verlieren. SQLite (>= 3.25, legacy_alter_table=OFF, hier Standard)
    passt dabei automatisch alle REFERENCES-Klauseln abhängiger Tabellen an
    (z. B. player_videos.player_id REFERENCES players -> player_profiles)."""
    if _table_exists(db, old_name) and not _table_exists(db, new_name):
        db.execute(f"ALTER TABLE {old_name} RENAME TO {new_name}")


def _rename_legacy_tables(db):
    """Frühere Tabellennamen (vor der Umbenennung auf player_profiles/
    club_profiles/player_stats) migrieren. Muss VOR dem Ausführen von
    schema.sql laufen, sonst legt CREATE TABLE IF NOT EXISTS bereits leere
    Tabellen unter dem neuen Namen an und die Umbenennung schlägt fehl."""
    _rename_table_if_needed(db, "players", "player_profiles")
    _rename_table_if_needed(db, "clubs", "club_profiles")
    _rename_table_if_needed(db, "statistics", "player_stats")


def _add_column_if_missing(db, table, column, ddl):
    existing = {row["name"] for row in db.execute(f"PRAGMA table_info({table})").fetchall()}
    if column not in existing:
        db.execute(f"ALTER TABLE {table} ADD COLUMN {ddl}")


def _migrate(db):
    """Leichte Migration für bestehende Datenbanken: CREATE TABLE IF NOT EXISTS
    in schema.sql legt neue Tabellen an, aber keine neuen Spalten in bereits
    vorhandenen Tabellen. Fehlende Spalten werden hier ergänzt."""
    _add_column_if_missing(db, "player_profiles", "is_demo", "is_demo INTEGER NOT NULL DEFAULT 0")
    _add_column_if_missing(db, "users", "last_login_at", "last_login_at TEXT")

    # Über seed.py angelegte Demo-Spieler nachträglich als solche kennzeichnen
    # (erkennbar an der E-Mail-Endung aus seed.py) – läuft bei jedem Start,
    # ist aber idempotent; echte/manuell angelegte Accounts bleiben unberührt.
    db.execute(
        """UPDATE player_profiles SET is_demo = 1 WHERE is_demo = 0 AND user_id IN (
             SELECT id FROM users WHERE email LIKE 'spieler%@test.scoutmatch.local'
           )"""
    )


def init_db(app):
    with app.app_context():
        db = get_db()
        _rename_legacy_tables(db)
        schema = SCHEMA_PATH.read_text(encoding="utf-8")
        db.executescript(schema)
        _migrate(db)
        db.commit()
    app.teardown_appcontext(close_db)
