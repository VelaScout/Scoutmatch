"""Eigenes Spielerprofil: Speichern, erneutes Abrufen, Leistungsdaten."""


def test_player_can_save_own_profile(register_player):
    c = register_player()
    res = c.put("/api/players/me", json={
        "hauptposition": "Stürmer", "liga": "Testliga", "wohnort": "Teststadt",
    })
    assert res.status_code == 200
    profile = c.get("/api/players/me").get_json()["player"]
    assert profile["hauptposition"] == "Stürmer"
    assert profile["liga"] == "Testliga"


def test_profile_changes_persist_after_reload(register_player, new_client):
    c = register_player(email="reload-test@example.com", password="Testpass123")
    c.put("/api/players/me", json={"aktueller_verein": "FC Reload"})

    # "Reload" simulieren: neuer Client (frische Session), erneut einloggen.
    fresh = new_client()
    fresh.post("/api/auth/login", json={"email": "reload-test@example.com", "password": "Testpass123"})
    profile = fresh.get("/api/players/me").get_json()["player"]
    assert profile["aktueller_verein"] == "FC Reload"


def test_player_can_save_and_retrieve_statistics(register_player):
    c = register_player()
    res = c.put("/api/players/me", json={
        "statistik": {"saison": "2025/26", "einsaetze": 10, "tore": 4, "assists": 2},
    })
    assert res.status_code == 200
    profile = c.get("/api/players/me").get_json()["player"]
    assert profile["statistiken"][0]["saison"] == "2025/26"
    assert profile["statistiken"][0]["tore"] == 4
    assert profile["statistiken"][0]["assists"] == 2
