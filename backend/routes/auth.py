"""Registrierung, Login, Logout, Session-Auskunft.

Sicherheitsprinzipien:
- Passwörter werden nie im Klartext gespeichert (bcrypt-Hash).
- Login-Fehler geben nie preis, ob die E-Mail existiert.
- Rate-Limits auf Login/Registrierung gegen Brute-Force.
- Rolle liegt serverseitig in der Session, nicht im Client editierbar.
"""
from datetime import datetime, timedelta, timezone

import bcrypt
from flask import Blueprint, jsonify, request, session

from backend.database.connection import get_db
from backend.extensions import limiter
from backend.services.mailer import send_mail
from backend.utils.security import (
    clean_int, clean_str, csrf_protect, hash_token, is_valid_email, is_valid_password, new_token,
)

bp = Blueprint("auth", __name__, url_prefix="/api/auth")

GENERIC_LOGIN_ERROR = "E-Mail-Adresse oder Passwort ist nicht korrekt."
GENERIC_RESET_MESSAGE = "Falls ein Konto mit dieser E-Mail-Adresse existiert, wurde eine E-Mail zum Zurücksetzen des Passworts gesendet."

EMAIL_VERIFICATION_HOURS = 48
PASSWORD_RESET_HOURS = 1


def _now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def _check_password(password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("utf-8"))
    except ValueError:
        return False


def _seed_verifications(db, user_id):
    for vtype in ("identitaet", "vereinszugehoerigkeit", "leistungsdaten"):
        db.execute(
            "INSERT INTO verifications (user_id, verification_type, status) VALUES (?, ?, 'selbst_angegeben')",
            (user_id, vtype),
        )


def _issue_token(db, table, user_id, hours):
    raw = new_token()
    expires_at = (datetime.now(timezone.utc) + timedelta(hours=hours)).isoformat(timespec="seconds")
    db.execute(
        f"INSERT INTO {table} (user_id, token_hash, expires_at) VALUES (?, ?, ?)",
        (user_id, hash_token(raw), expires_at),
    )
    return raw


def _consume_token(db, table, raw_token):
    """Prüft Gültigkeit (existiert, nicht abgelaufen, nicht verbraucht) und
    markiert das Token sofort als verbraucht. Gibt die user_id zurück oder
    None, wenn das Token ungültig ist."""
    row = db.execute(
        f"SELECT id, user_id, expires_at, used_at FROM {table} WHERE token_hash = ?",
        (hash_token(raw_token),),
    ).fetchone()
    if not row or row["used_at"]:
        return None
    if row["expires_at"] < _now():
        return None
    db.execute(f"UPDATE {table} SET used_at = ? WHERE id = ?", (_now(), row["id"]))
    return row["user_id"]


def _send_verification_email(db, user_id, email):
    raw = _issue_token(db, "email_verification_tokens", user_id, EMAIL_VERIFICATION_HOURS)
    link = f"/e-mail-bestaetigen.html?token={raw}"
    send_mail(
        db,
        email,
        "Bestätige deine E-Mail-Adresse – ScoutMatch",
        f"Bitte bestätige deine E-Mail-Adresse über folgenden Link (lokale Entwicklungsumgebung):\n\n"
        f"http://127.0.0.1:5001{link}\n\nDer Link ist {EMAIL_VERIFICATION_HOURS} Stunden gültig.",
        email_type="email_verification",
    )


@bp.get("/csrf-token")
def csrf_token():
    from backend.utils.security import get_csrf_token
    return jsonify(csrf_token=get_csrf_token())


@bp.post("/register/player")
@limiter.limit("10 per hour")
def register_player():
    data = request.get_json(silent=True) or {}

    email = clean_str(data.get("email"), 254)
    password = data.get("password") or ""
    password_confirm = data.get("password_confirm") or ""
    accept_terms = bool(data.get("accept_terms"))
    accept_privacy = bool(data.get("accept_privacy"))

    if not is_valid_email(email):
        return jsonify(error="Bitte gib eine gültige E-Mail-Adresse an."), 400
    if not is_valid_password(password):
        return jsonify(error="Das Passwort muss zwischen 8 und 128 Zeichen lang sein."), 400
    if password != password_confirm:
        return jsonify(error="Die Passwörter stimmen nicht überein."), 400
    if not (accept_terms and accept_privacy):
        return jsonify(error="Bitte bestätige die Nutzungsbedingungen und die Datenschutzerklärung."), 400

    vorname = clean_str(data.get("vorname"), 100)
    nachname = clean_str(data.get("nachname"), 100)
    if not vorname or not nachname:
        return jsonify(error="Bitte gib Vor- und Nachnamen an."), 400

    db = get_db()
    existing = db.execute("SELECT id FROM users WHERE email = ?", (email.lower(),)).fetchone()
    if existing:
        # Bewusst derselbe generische Fehler wie bei falschem Login –
        # kein Rückschluss darauf, ob die Adresse bereits registriert ist.
        return jsonify(error="Registrierung nicht möglich. Bitte prüfe deine Angaben."), 400

    password_hash = _hash_password(password)
    now = _now()

    cur = db.execute(
        "INSERT INTO users (email, password_hash, role, created_at, updated_at) VALUES (?, ?, 'player', ?, ?)",
        (email.lower(), password_hash, now, now),
    )
    user_id = cur.lastrowid

    db.execute(
        """INSERT INTO player_profiles (
            user_id, vorname, nachname, geburtsdatum, wohnort, nationalitaet,
            hauptposition, nebenposition, aktueller_verein, liga, groesse, gewicht,
            starker_fuss, vertragsstatus, vertragsende, verfuegbar_ab, wechselstatus, profil_sichtbar,
            created_at, updated_at
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,1,?,?)""",
        (
            user_id, vorname, nachname,
            clean_str(data.get("geburtsdatum"), 20),
            clean_str(data.get("wohnort"), 120),
            clean_str(data.get("nationalitaet"), 80),
            clean_str(data.get("hauptposition"), 60),
            clean_str(data.get("nebenposition"), 60),
            clean_str(data.get("aktueller_verein"), 120),
            clean_str(data.get("liga"), 120),
            clean_int(data.get("groesse"), 100, 230),
            clean_int(data.get("gewicht"), 30, 200),
            clean_str(data.get("starker_fuss"), 20),
            clean_str(data.get("vertragsstatus"), 40),
            clean_str(data.get("vertragsende"), 20),
            clean_str(data.get("verfuegbar_ab"), 20),
            clean_str(data.get("wechselstatus"), 40),
            now, now,
        ),
    )
    _seed_verifications(db, user_id)
    _send_verification_email(db, user_id, email.lower())
    db.commit()

    session.clear()
    session["user_id"] = user_id
    session["role"] = "player"
    session.permanent = True

    return jsonify(ok=True, role="player", redirect="preise.html?type=spieler"), 201


@bp.post("/register/club")
@limiter.limit("10 per hour")
def register_club():
    data = request.get_json(silent=True) or {}

    email = clean_str(data.get("email"), 254)
    password = data.get("password") or ""
    password_confirm = data.get("password_confirm") or ""
    accept_terms = bool(data.get("accept_terms"))
    accept_privacy = bool(data.get("accept_privacy"))

    if not is_valid_email(email):
        return jsonify(error="Bitte gib eine gültige E-Mail-Adresse an."), 400
    if not is_valid_password(password):
        return jsonify(error="Das Passwort muss zwischen 8 und 128 Zeichen lang sein."), 400
    if password != password_confirm:
        return jsonify(error="Die Passwörter stimmen nicht überein."), 400
    if not (accept_terms and accept_privacy):
        return jsonify(error="Bitte bestätige die Nutzungsbedingungen und die Datenschutzerklärung."), 400

    vereinsname = clean_str(data.get("vereinsname"), 150)
    ansprechpartner_vorname = clean_str(data.get("ansprechpartner_vorname"), 100)
    ansprechpartner_nachname = clean_str(data.get("ansprechpartner_nachname"), 100)
    if not vereinsname or not ansprechpartner_vorname or not ansprechpartner_nachname:
        return jsonify(error="Bitte fülle Vereinsname und Ansprechpartner aus."), 400

    db = get_db()
    existing = db.execute("SELECT id FROM users WHERE email = ?", (email.lower(),)).fetchone()
    if existing:
        return jsonify(error="Registrierung nicht möglich. Bitte prüfe deine Angaben."), 400

    password_hash = _hash_password(password)
    now = _now()

    cur = db.execute(
        "INSERT INTO users (email, password_hash, role, created_at, updated_at) VALUES (?, ?, 'club', ?, ?)",
        (email.lower(), password_hash, now, now),
    )
    user_id = cur.lastrowid

    db.execute(
        """INSERT INTO club_profiles (
            user_id, vereinsname, liga, ort, website,
            ansprechpartner_vorname, ansprechpartner_nachname, funktion,
            verification_status, created_at, updated_at
        ) VALUES (?,?,?,?,?,?,?,?, 'pending', ?, ?)""",
        (
            user_id, vereinsname,
            clean_str(data.get("liga"), 120),
            clean_str(data.get("ort"), 120),
            clean_str(data.get("website"), 200),
            ansprechpartner_vorname, ansprechpartner_nachname,
            clean_str(data.get("funktion"), 60),
            now, now,
        ),
    )
    _send_verification_email(db, user_id, email.lower())
    db.commit()

    session.clear()
    session["user_id"] = user_id
    session["role"] = "club"
    session.permanent = True

    return jsonify(ok=True, role="club", redirect="preise.html?type=verein"), 201


@bp.post("/login")
@limiter.limit("10 per 5 minutes")
def login():
    data = request.get_json(silent=True) or {}
    email = clean_str(data.get("email"), 254)
    password = data.get("password") or ""

    if not email or not password:
        return jsonify(error=GENERIC_LOGIN_ERROR), 401

    db = get_db()
    user = db.execute("SELECT * FROM users WHERE email = ?", (email.lower(),)).fetchone()

    if not user or not _check_password(password, user["password_hash"]):
        return jsonify(error=GENERIC_LOGIN_ERROR), 401

    if user["is_locked"]:
        return jsonify(error="Dieser Account ist gesperrt. Bitte kontaktiere den Support."), 403

    db.execute("UPDATE users SET last_login_at = ? WHERE id = ?", (_now(), user["id"]))
    db.commit()

    session.clear()
    session["user_id"] = user["id"]
    session["role"] = user["role"]
    session.permanent = True

    redirect = {
        "player": "spieler-dashboard.html",
        "club": "vereins-dashboard.html",
        "admin": "admin.html",
    }.get(user["role"], "index.html")

    return jsonify(ok=True, role=user["role"], redirect=redirect)


@bp.post("/logout")
def logout():
    session.clear()
    return jsonify(ok=True)


@bp.post("/change-password")
@limiter.limit("10 per hour")
def change_password():
    user_id = session.get("user_id")
    if not user_id:
        return jsonify(error="Nicht angemeldet."), 401
    csrf_err = csrf_protect()
    if csrf_err:
        return csrf_err

    data = request.get_json(silent=True) or {}
    current_password = data.get("current_password") or ""
    new_password = data.get("new_password") or ""
    new_password_confirm = data.get("new_password_confirm") or ""

    if not is_valid_password(new_password):
        return jsonify(error="Das neue Passwort muss zwischen 8 und 128 Zeichen lang sein."), 400
    if new_password != new_password_confirm:
        return jsonify(error="Die neuen Passwörter stimmen nicht überein."), 400

    db = get_db()
    user = db.execute("SELECT id, password_hash FROM users WHERE id = ?", (user_id,)).fetchone()
    if not user or not _check_password(current_password, user["password_hash"]):
        return jsonify(error="Das aktuelle Passwort ist nicht korrekt."), 401

    db.execute(
        "UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?",
        (_hash_password(new_password), _now(), user_id),
    )
    db.commit()
    return jsonify(ok=True)


@bp.post("/delete-account")
@limiter.limit("5 per hour")
def delete_account():
    user_id = session.get("user_id")
    if not user_id:
        return jsonify(error="Nicht angemeldet."), 401
    csrf_err = csrf_protect()
    if csrf_err:
        return csrf_err

    data = request.get_json(silent=True) or {}
    password = data.get("password") or ""

    db = get_db()
    user = db.execute("SELECT id, password_hash FROM users WHERE id = ?", (user_id,)).fetchone()
    if not user or not _check_password(password, user["password_hash"]):
        return jsonify(error="Das eingegebene Passwort ist nicht korrekt."), 401

    db.execute("DELETE FROM users WHERE id = ?", (user_id,))
    db.commit()
    session.clear()
    return jsonify(ok=True)


@bp.get("/me")
def me():
    user_id = session.get("user_id")
    if not user_id:
        return jsonify(authenticated=False), 200

    db = get_db()
    user = db.execute("SELECT id, email, role, email_verified, is_locked FROM users WHERE id = ?", (user_id,)).fetchone()
    if not user or user["is_locked"]:
        session.clear()
        return jsonify(authenticated=False), 200

    profile_name = None
    verification_status = None
    if user["role"] == "player":
        p = db.execute("SELECT vorname, nachname FROM player_profiles WHERE user_id = ?", (user_id,)).fetchone()
        if p:
            profile_name = f"{p['vorname'] or ''} {p['nachname'] or ''}".strip()
    elif user["role"] == "club":
        c = db.execute("SELECT vereinsname, verification_status FROM club_profiles WHERE user_id = ?", (user_id,)).fetchone()
        if c:
            profile_name = c["vereinsname"]
            verification_status = c["verification_status"]

    return jsonify(
        authenticated=True,
        id=user["id"],
        email=user["email"],
        role=user["role"],
        email_verified=bool(user["email_verified"]),
        name=profile_name,
        verification_status=verification_status,
    )


@bp.post("/verify-email")
@limiter.limit("20 per hour")
def verify_email():
    data = request.get_json(silent=True) or {}
    token = clean_str(data.get("token"), 200)
    if not token:
        return jsonify(error="Kein Token übermittelt."), 400

    db = get_db()
    user_id = _consume_token(db, "email_verification_tokens", token)
    if not user_id:
        return jsonify(error="Der Bestätigungslink ist ungültig oder abgelaufen."), 400

    db.execute("UPDATE users SET email_verified = 1, updated_at = ? WHERE id = ?", (_now(), user_id))
    db.commit()
    return jsonify(ok=True)


@bp.post("/resend-verification")
@limiter.limit("5 per hour")
def resend_verification():
    user_id = session.get("user_id")
    if not user_id:
        return jsonify(error="Nicht angemeldet."), 401
    csrf_err = csrf_protect()
    if csrf_err:
        return csrf_err

    db = get_db()
    user = db.execute("SELECT id, email, email_verified FROM users WHERE id = ?", (user_id,)).fetchone()
    if not user:
        return jsonify(error="Nicht angemeldet."), 401
    if user["email_verified"]:
        return jsonify(error="Diese E-Mail-Adresse ist bereits bestätigt."), 400

    _send_verification_email(db, user["id"], user["email"])
    db.commit()
    return jsonify(ok=True)


@bp.post("/forgot-password")
@limiter.limit("5 per hour")
def forgot_password():
    data = request.get_json(silent=True) or {}
    email = clean_str(data.get("email"), 254)
    if not email:
        return jsonify(error="Bitte gib eine E-Mail-Adresse an."), 400

    db = get_db()
    user = db.execute("SELECT id, email FROM users WHERE email = ?", (email.lower(),)).fetchone()

    # Bewusst IMMER dieselbe Antwort, unabhängig davon, ob die E-Mail
    # existiert – sonst ließe sich über diesen Endpunkt erraten, welche
    # Adressen registriert sind.
    if user:
        raw = _issue_token(db, "password_reset_tokens", user["id"], PASSWORD_RESET_HOURS)
        link = f"/passwort-zuruecksetzen.html?token={raw}"
        send_mail(
            db,
            user["email"],
            "Passwort zurücksetzen – ScoutMatch",
            f"Du hast eine Passwort-Zurücksetzung angefordert (lokale Entwicklungsumgebung):\n\n"
            f"http://127.0.0.1:5001{link}\n\nDer Link ist {PASSWORD_RESET_HOURS} Stunde(n) gültig. "
            f"Falls du das nicht warst, kannst du diese E-Mail ignorieren.",
            email_type="password_reset",
        )
        db.commit()

    return jsonify(ok=True, message=GENERIC_RESET_MESSAGE)


@bp.post("/reset-password")
@limiter.limit("10 per hour")
def reset_password():
    data = request.get_json(silent=True) or {}
    token = clean_str(data.get("token"), 200)
    password = data.get("password") or ""
    password_confirm = data.get("password_confirm") or ""

    if not token:
        return jsonify(error="Kein Token übermittelt."), 400
    if not is_valid_password(password):
        return jsonify(error="Das Passwort muss zwischen 8 und 128 Zeichen lang sein."), 400
    if password != password_confirm:
        return jsonify(error="Die Passwörter stimmen nicht überein."), 400

    db = get_db()
    user_id = _consume_token(db, "password_reset_tokens", token)
    if not user_id:
        return jsonify(error="Der Link ist ungültig oder abgelaufen. Bitte fordere einen neuen an."), 400

    db.execute(
        "UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?",
        (_hash_password(password), _now(), user_id),
    )
    # Alle anderen noch offenen Reset-Tokens dieses Nutzers ebenfalls entwerten.
    db.execute(
        "UPDATE password_reset_tokens SET used_at = ? WHERE user_id = ? AND used_at IS NULL",
        (_now(), user_id),
    )
    db.commit()
    return jsonify(ok=True)
