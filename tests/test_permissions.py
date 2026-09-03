"""Serverseitige Rollen- und Freigabe-Prüfungen. requireRole() im Frontend ist
reiner UX-Komfort – diese Tests prüfen die echte, serverseitige Kontrolle."""
from tests.conftest import approve_club


def test_player_cannot_open_admin_route(register_player):
    c = register_player()
    res = c.get("/api/admin/users")
    assert res.status_code in (401, 403)


def test_club_cannot_open_admin_route(register_club):
    c = register_club()
    res = c.get("/api/admin/users")
    assert res.status_code in (401, 403)


def test_player_cannot_edit_another_players_profile(register_player):
    """Es gibt keine Route, um ein fremdes Profil per ID zu bearbeiten –
    PUT /api/players/me wirkt immer nur auf das eigene Profil. Das wird hier
    positiv nachgewiesen: Spieler B bleibt unverändert, wenn Spieler A sein
    eigenes Profil speichert."""
    a = register_player(email="spielerA@example.com")
    b = register_player(email="spielerB@example.com", nachname="Original")

    res = a.put("/api/players/me", json={"nachname": "VonAGeaendert"})
    assert res.status_code == 200

    b_profile = b.get("/api/players/me").get_json()["player"]
    assert b_profile["nachname"] == "Original"


def test_unapproved_club_cannot_use_full_search(app, register_club):
    c = register_club(email="pending-club@example.com")
    res = c.get("/api/players/search")
    assert res.status_code == 403


def test_approved_club_can_use_search(app, register_club):
    c = register_club(email="approved-club@example.com")
    approve_club(app, "approved-club@example.com")
    res = c.get("/api/players/search")
    assert res.status_code == 200
    assert "players" in res.get_json()
