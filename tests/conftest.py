"""Gemeinsame Test-Fixtures.

Jeder Test bekommt eine FRISCHE, ISOLIERTE SQLite-Datenbank in einem
temporären Verzeichnis (pytest tmp_path) – niemals die echte Entwicklungs-
datenbank unter instance/scoutmatch.db. Nach dem Test räumt pytest tmp_path
automatisch auf; es bleiben keine Testnutzer in der normalen Datenbank
zurück.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import bcrypt
import pytest

from app import create_app
from backend.database.connection import get_db
from config import TestConfig


@pytest.fixture()
def app(tmp_path):
    application = create_app(
        config_class=TestConfig,
        config_overrides={
            "DATABASE_PATH": str(tmp_path / "test.db"),
            "SESSION_FILE_DIR": str(tmp_path / "flask_session"),
        },
    )
    yield application


class ApiClient:
    """Kleiner Wrapper um den Flask-Testclient, der sich wie assets/api.js
    verhält: holt sich vor jeder verändernden Anfrage ein CSRF-Token aus der
    eigenen Session und schickt es im Header mit.

    Bewusst OHNE Caching: Login/Registrierung rufen serverseitig
    session.clear() auf und entwerten damit ein zuvor geholtes Token – ein
    gecachter Wert wäre nach dem ersten Login/Register-Aufruf im selben
    Client veraltet und würde jede folgende Schreibanfrage mit 403
    (CSRF-Fehler) scheitern lassen."""

    def __init__(self, client):
        self.client = client

    def _headers(self):
        res = self.client.get("/api/auth/csrf-token")
        return {"X-CSRF-Token": res.get_json()["csrf_token"]}

    def get(self, url, **kw):
        return self.client.get(url, **kw)

    def post(self, url, json=None, **kw):
        return self.client.post(url, json=json, headers=self._headers(), **kw)

    def put(self, url, json=None, **kw):
        return self.client.put(url, json=json, headers=self._headers(), **kw)

    def delete(self, url, **kw):
        return self.client.delete(url, headers=self._headers(), **kw)


@pytest.fixture()
def api(app):
    """Ein eingeloggter/anonymer API-Client mit eigenen Cookies."""
    return ApiClient(app.test_client())


@pytest.fixture()
def new_client(app):
    """Factory für weitere, unabhängige Clients auf derselben Test-App –
    z. B. um Verein und Spieler gleichzeitig in einem Test einzuloggen."""
    def _make():
        return ApiClient(app.test_client())
    return _make


@pytest.fixture()
def register_player(app, new_client):
    def _make(email="spieler@example.com", password="Testpass123", **overrides):
        c = new_client()
        payload = {
            "email": email, "password": password, "password_confirm": password,
            "vorname": "Test", "nachname": "Spieler",
            "accept_terms": True, "accept_privacy": True,
        }
        payload.update(overrides)
        res = c.post("/api/auth/register/player", json=payload)
        assert res.status_code == 201, res.get_json()
        return c
    return _make


@pytest.fixture()
def register_club(app, new_client):
    def _make(email="verein@example.com", password="Testpass123", **overrides):
        c = new_client()
        payload = {
            "email": email, "password": password, "password_confirm": password,
            "vereinsname": "Test FC", "ansprechpartner_vorname": "Ansp",
            "ansprechpartner_nachname": "Rechner", "liga": "Testliga", "ort": "Teststadt",
            "accept_terms": True, "accept_privacy": True,
        }
        payload.update(overrides)
        res = c.post("/api/auth/register/club", json=payload)
        assert res.status_code == 201, res.get_json()
        return c
    return _make


@pytest.fixture()
def admin_client(app, new_client):
    """Legt direkt in der isolierten Test-DB ein Admin-Konto an (analog zu
    create_admin.py) und gibt einen bereits eingeloggten Client zurück."""
    with app.app_context():
        db = get_db()
        pw_hash = bcrypt.hashpw(b"AdminPass123", bcrypt.gensalt()).decode("utf-8")
        db.execute(
            "INSERT INTO users (email, password_hash, role, email_verified) VALUES (?, ?, 'admin', 1)",
            ("admin@example.com", pw_hash),
        )
        db.commit()
    c = new_client()
    res = c.post("/api/auth/login", json={"email": "admin@example.com", "password": "AdminPass123"})
    assert res.status_code == 200, res.get_json()
    return c


def approve_club(app, club_email):
    """Test-Helfer: setzt den Verifizierungsstatus eines Vereins direkt in
    der DB auf 'verified' (kürzer als jedes Mal über die Admin-API zu gehen,
    wenn nur der Endzustand relevant ist)."""
    with app.app_context():
        db = get_db()
        db.execute(
            """UPDATE club_profiles SET verification_status = 'verified'
               WHERE user_id = (SELECT id FROM users WHERE email = ?)""",
            (club_email,),
        )
        db.commit()
