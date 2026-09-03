"""Favoriten (nur Vereine)."""
from tests.conftest import approve_club


def _make_visible_player(register_player, email="fav-player@example.com"):
    p = register_player(email=email)
    p.put("/api/players/me", json={"profil_sichtbar": True})
    return p.get("/api/players/me").get_json()["player"]["id"]


def test_club_can_add_favorite(app, register_club, register_player):
    club = register_club(email="fav-club@example.com")
    approve_club(app, "fav-club@example.com")
    player_id = _make_visible_player(register_player)

    res = club.post("/api/favorites", json={"player_id": player_id})
    assert res.status_code == 201

    favorites = club.get("/api/favorites").get_json()["favorites"]
    assert any(f["id"] == player_id for f in favorites)


def test_duplicate_favorite_is_prevented(app, register_club, register_player):
    club = register_club(email="fav-club2@example.com")
    approve_club(app, "fav-club2@example.com")
    player_id = _make_visible_player(register_player, email="fav-player2@example.com")

    club.post("/api/favorites", json={"player_id": player_id})
    res = club.post("/api/favorites", json={"player_id": player_id})
    assert res.status_code == 409


def test_favorite_can_be_removed(app, register_club, register_player):
    club = register_club(email="fav-club3@example.com")
    approve_club(app, "fav-club3@example.com")
    player_id = _make_visible_player(register_player, email="fav-player3@example.com")

    add = club.post("/api/favorites", json={"player_id": player_id})
    favorite_id = add.get_json()["favorite_id"]

    res = club.delete(f"/api/favorites/{favorite_id}")
    assert res.status_code == 200

    favorites = club.get("/api/favorites").get_json()["favorites"]
    assert not any(f["id"] == player_id for f in favorites)
