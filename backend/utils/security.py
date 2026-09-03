"""Gemeinsame Hilfsfunktionen: Auth-Guards, CSRF, Validierung."""
import hashlib
import re
import secrets
from functools import wraps

from flask import g, jsonify, request, session

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _session_user_active():
    """Prüft bei JEDER Anfrage neu (nicht nur beim Login), dass der Nutzer
    noch existiert und nicht gesperrt ist. Ohne diese Prüfung würde eine
    bereits bestehende Session eines zwischenzeitlich von einem Admin
    gesperrten Kontos weiterhin funktionieren – die Sperre griffe dann erst
    beim nächsten Login, nicht sofort."""
    if "_user_active_checked" in g:
        return g._user_active_checked
    from backend.database.connection import get_db
    db = get_db()
    row = db.execute("SELECT is_locked FROM users WHERE id = ?", (session.get("user_id"),)).fetchone()
    g._user_active_checked = bool(row) and not row["is_locked"]
    return g._user_active_checked


# ------------------------------------------------------------ Tokens ------
# Für E-Mail-Verifizierung und Passwort-Reset: Es wird nie der Rohwert des
# Tokens gespeichert, sondern nur sein SHA-256-Hash. Der Rohwert existiert
# ausschließlich im (Mock-)E-Mail-Link – ein Datenbank-Leak allein genügt
# damit nicht, um ein gültiges Token zu erhalten.

def new_token():
    return secrets.token_urlsafe(32)


def hash_token(raw_token):
    return hashlib.sha256(raw_token.encode("utf-8")).hexdigest()


# ---------------------------------------------------------------- Auth ----

def login_required(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        if not session.get("user_id"):
            return jsonify(error="Nicht angemeldet."), 401
        if not _session_user_active():
            session.clear()
            return jsonify(error="Dieser Account ist gesperrt oder existiert nicht mehr."), 403
        return fn(*args, **kwargs)
    return wrapper


def role_required(*roles):
    """Serverseitige Rollenprüfung. Muss auf JEDER geschützten Route liegen –
    das ist die eigentliche Zugriffskontrolle, nicht das Verstecken von Links
    im Frontend. Prüft bei jeder Anfrage auch, ob das Konto zwischenzeitlich
    gesperrt wurde – nicht nur beim Login."""
    def decorator(fn):
        @wraps(fn)
        def wrapper(*args, **kwargs):
            if not session.get("user_id"):
                return jsonify(error="Nicht angemeldet."), 401
            if not _session_user_active():
                session.clear()
                return jsonify(error="Dieser Account ist gesperrt oder existiert nicht mehr."), 403
            if session.get("role") not in roles:
                return jsonify(error="Kein Zugriff für diese Rolle."), 403
            return fn(*args, **kwargs)
        return wrapper
    return decorator


# ---------------------------------------------------------------- CSRF ----
# Synchronizer-Token-Pattern: Token liegt serverseitig in der Session,
# das Frontend muss ihn bei jeder verändernden Anfrage im Header mitschicken.

def get_csrf_token():
    if "csrf_token" not in session:
        session["csrf_token"] = secrets.token_hex(32)
    return session["csrf_token"]


def csrf_protect():
    if request.method in ("POST", "PUT", "PATCH", "DELETE"):
        header_token = request.headers.get("X-CSRF-Token", "")
        session_token = session.get("csrf_token", "")
        if not session_token or not secrets.compare_digest(header_token, session_token):
            return jsonify(error="Ungültiges oder fehlendes CSRF-Token."), 403
    return None


# ------------------------------------------------------------ Validierung --

def is_valid_email(value):
    return bool(value) and len(value) <= 254 and bool(EMAIL_RE.match(value))


def is_valid_password(value):
    # Bewusst einfache, transparente Mindestanforderung fürs MVP.
    return bool(value) and 8 <= len(value) <= 128


def clean_str(value, max_len=200):
    """Whitespace trimmen und Länge begrenzen. Escaping übernimmt beim Anzeigen
    das Frontend (textContent) bzw. JSON-Encoding – hier geht es nur um
    Plausibilität/Länge der Eingabe."""
    if value is None:
        return None
    value = str(value).strip()
    if not value:
        return None
    return value[:max_len]


def clean_int(value, min_v=None, max_v=None):
    try:
        n = int(value)
    except (TypeError, ValueError):
        return None
    if min_v is not None and n < min_v:
        return None
    if max_v is not None and n > max_v:
        return None
    return n
