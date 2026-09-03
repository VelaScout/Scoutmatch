"""Admin-Aktionen und deren Protokollierung in admin_audit_log."""


def test_admin_can_approve_club(admin_client, register_club):
    register_club(email="approve-me@example.com")
    clubs = admin_client.get("/api/admin/clubs").get_json()["clubs"]
    club_id = next(c["id"] for c in clubs if c["email"] == "approve-me@example.com")

    res = admin_client.put(f"/api/admin/clubs/{club_id}/verification", json={"status": "verified"})
    assert res.status_code == 200

    clubs = admin_client.get("/api/admin/clubs").get_json()["clubs"]
    updated = next(c for c in clubs if c["id"] == club_id)
    assert updated["verification_status"] == "verified"


def test_admin_can_verify_player(admin_client, register_player):
    register_player(email="verify-me@example.com")
    players = admin_client.get("/api/admin/players").get_json()["players"]
    player_id = next(p["id"] for p in players if p["email"] == "verify-me@example.com")

    res = admin_client.put(
        f"/api/admin/players/{player_id}/verification",
        json={"verification_type": "identitaet", "status": "verifiziert"},
    )
    assert res.status_code == 200

    players = admin_client.get("/api/admin/players").get_json()["players"]
    updated = next(p for p in players if p["id"] == player_id)
    assert updated["verifizierung"]["identitaet"] == "verifiziert"


def test_admin_can_lock_user(admin_client, register_player, new_client):
    register_player(email="lock-me@example.com", password="Testpass123")
    users = admin_client.get("/api/admin/users").get_json()["users"]
    user_id = next(u["id"] for u in users if u["email"] == "lock-me@example.com")

    res = admin_client.put(f"/api/admin/users/{user_id}/lock", json={"locked": True})
    assert res.status_code == 200

    fresh = new_client()
    login = fresh.post("/api/auth/login", json={"email": "lock-me@example.com", "password": "Testpass123"})
    assert login.status_code == 403


def test_admin_action_creates_audit_log_entry(admin_client, register_club):
    register_club(email="audit-me@example.com")
    clubs = admin_client.get("/api/admin/clubs").get_json()["clubs"]
    club_id = next(c["id"] for c in clubs if c["email"] == "audit-me@example.com")

    admin_client.put(f"/api/admin/clubs/{club_id}/verification", json={"status": "verified"})

    entries = admin_client.get("/api/admin/audit-log").get_json()["entries"]
    assert any(
        e["action"] == "club_approved" and e["target_type"] == "club" and e["target_id"] == club_id
        for e in entries
    )
