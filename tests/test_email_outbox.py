"""Dev-Postausgang (email_outbox) für Verifizierungs- und Reset-E-Mails."""


def test_verification_email_lands_in_outbox(admin_client, register_player):
    register_player(email="outbox-verify@example.com")

    emails = admin_client.get("/api/admin/outbox").get_json()["emails"]
    assert any(
        e["recipient"] == "outbox-verify@example.com" and e["email_type"] == "email_verification"
        for e in emails
    )


def test_password_reset_email_lands_in_outbox(admin_client, register_player, new_client):
    register_player(email="outbox-reset@example.com")
    c = new_client()
    c.post("/api/auth/forgot-password", json={"email": "outbox-reset@example.com"})

    emails = admin_client.get("/api/admin/outbox").get_json()["emails"]
    assert any(
        e["recipient"] == "outbox-reset@example.com" and e["email_type"] == "password_reset"
        for e in emails
    )
