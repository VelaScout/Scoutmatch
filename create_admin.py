"""Legt lokal ein Admin-Konto an. Es gibt bewusst KEINE öffentliche
Admin-Registrierung über die Website – Admin-Konten müssen lokal von Hand
angelegt werden.

Verwendung:
    source venv/bin/activate
    python3 create_admin.py admin@test.scoutmatch.local Test1234!

Ohne Argumente wird ein Standard-Testkonto angelegt:
    admin@test.scoutmatch.local / Test1234!
"""
import sys
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

import bcrypt

BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "instance" / "scoutmatch.db"


def main():
    email = sys.argv[1] if len(sys.argv) > 1 else "admin@test.scoutmatch.local"
    password = sys.argv[2] if len(sys.argv) > 2 else "Test1234!"

    if not DB_PATH.exists():
        raise SystemExit(
            "Datenbank nicht gefunden unter " + str(DB_PATH) +
            ". Bitte zuerst den Server einmal starten (python3 app.py)."
        )

    db = sqlite3.connect(str(DB_PATH))
    existing = db.execute("SELECT id FROM users WHERE email = ?", (email.lower(),)).fetchone()
    if existing:
        db.execute("UPDATE users SET role = 'admin' WHERE email = ?", (email.lower(),))
        db.commit()
        print(f"Bestehendes Konto {email} wurde zum Admin gemacht.")
        return

    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    password_hash = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")
    db.execute(
        "INSERT INTO users (email, password_hash, role, email_verified, created_at, updated_at) "
        "VALUES (?, ?, 'admin', 1, ?, ?)",
        (email.lower(), password_hash, now, now),
    )
    db.commit()
    print(f"Admin-Konto angelegt: {email} (Passwort: {password})")


if __name__ == "__main__":
    main()
