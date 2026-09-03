"""Kontaktanfragen: Verein -> Spieler, Annahme/Ablehnung, Datenschutz."""
from tests.conftest import approve_club


def _setup(app, register_club, register_player, club_email="cr-club@example.com",
           player_email="cr-player@example.com"):
    club = register_club(email=club_email)
    approve_club(app, club_email)
    player = register_player(email=player_email)
    player.put("/api/players/me", json={"profil_sichtbar": True})
    player_id = player.get("/api/players/me").get_json()["player"]["id"]
    return club, player, player_id


def test_club_can_send_contact_request(app, register_club, register_player):
    club, player, player_id = _setup(app, register_club, register_player)
    res = club.post("/api/contact-requests", json={"player_id": player_id, "message": "Interesse!"})
    assert res.status_code == 201


def test_player_sees_incoming_request(app, register_club, register_player):
    club, player, player_id = _setup(
        app, register_club, register_player,
        club_email="cr-club2@example.com", player_email="cr-player2@example.com",
    )
    club.post("/api/contact-requests", json={"player_id": player_id, "message": "Interesse!"})

    requests = player.get("/api/contact-requests").get_json()["requests"]
    assert len(requests) == 1
    assert requests[0]["status"] == "pending"


def test_contact_data_hidden_before_acceptance(app, register_club, register_player):
    club, player, player_id = _setup(
        app, register_club, register_player,
        club_email="cr-club3@example.com", player_email="cr-player3@example.com",
    )
    club.post("/api/contact-requests", json={"player_id": player_id})

    club_view = club.get("/api/contact-requests").get_json()["requests"]
    assert club_view[0]["player_email"] is None


def test_contact_data_visible_after_acceptance(app, register_club, register_player):
    club, player, player_id = _setup(
        app, register_club, register_player,
        club_email="cr-club4@example.com", player_email="cr-player4@example.com",
    )
    club.post("/api/contact-requests", json={"player_id": player_id})

    requests = player.get("/api/contact-requests").get_json()["requests"]
    request_id = requests[0]["id"]

    accept = player.put(f"/api/contact-requests/{request_id}", json={"status": "accepted"})
    assert accept.status_code == 200

    club_view = club.get("/api/contact-requests").get_json()["requests"]
    assert club_view[0]["status"] == "accepted"
    assert club_view[0]["player_email"] == "cr-player4@example.com"
