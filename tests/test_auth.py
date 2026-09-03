"""Registrierung, Login/Logout, Session-Auskunft."""


def test_player_registration_succeeds(register_player):
    c = register_player(email="neuer.spieler@example.com")
    me = c.get("/api/auth/me").get_json()
    assert me["authenticated"] is True
    assert me["role"] == "player"
    assert me["email"] == "neuer.spieler@example.com"


def test_club_registration_succeeds(register_club):
    c = register_club(email="neuer.verein@example.com")
    me = c.get("/api/auth/me").get_json()
    assert me["authenticated"] is True
    assert me["role"] == "club"
    assert me["verification_status"] == "pending"


def test_duplicate_email_is_rejected(register_player, new_client):
    register_player(email="doppelt@example.com")
    c2 = new_client()
    res = c2.post("/api/auth/register/player", json={
        "email": "doppelt@example.com", "password": "Testpass123", "password_confirm": "Testpass123",
        "vorname": "Zweiter", "nachname": "Versuch", "accept_terms": True, "accept_privacy": True,
    })
    assert res.status_code == 400


def test_login_with_correct_password(register_player, new_client):
    register_player(email="login-ok@example.com", password="Testpass123")
    c = new_client()
    res = c.post("/api/auth/login", json={"email": "login-ok@example.com", "password": "Testpass123"})
    assert res.status_code == 200
    assert res.get_json()["role"] == "player"


def test_login_with_wrong_password_is_rejected(register_player, new_client):
    register_player(email="login-fail@example.com", password="Testpass123")
    c = new_client()
    res = c.post("/api/auth/login", json={"email": "login-fail@example.com", "password": "FalschesPasswort1"})
    assert res.status_code == 401


def test_unverified_account_can_login_but_is_flagged(register_player):
    # Design-Entscheidung: Login ist auch ohne bestätigte E-Mail möglich
    # (das Frontend zeigt stattdessen einen Hinweis-Banner) – gesperrt wird
    # nur bei is_locked. /me muss den unbestätigten Status aber korrekt melden.
    c = register_player(email="unverified@example.com")
    me = c.get("/api/auth/me").get_json()
    assert me["authenticated"] is True
    assert me["email_verified"] is False


def test_logout_clears_session(register_player):
    c = register_player(email="logout-test@example.com")
    assert c.get("/api/auth/me").get_json()["authenticated"] is True
    res = c.post("/api/auth/logout")
    assert res.status_code == 200
    assert c.get("/api/auth/me").get_json()["authenticated"] is False
