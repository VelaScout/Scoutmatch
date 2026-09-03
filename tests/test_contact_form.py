"""Öffentliches Kontaktformular (kontakt.html -> POST /api/public/contact)."""


def test_valid_contact_message_is_stored(app, api):
    res = api.post("/api/public/contact", json={
        "name": "Maria Muster", "email": "maria@example.com", "message": "Eine Testnachricht.",
    })
    assert res.status_code == 200

    from backend.database.connection import get_db
    with app.app_context():
        row = get_db().execute(
            "SELECT name, email, message FROM contact_messages WHERE email = ?", ("maria@example.com",)
        ).fetchone()
    assert row is not None
    assert row["message"] == "Eine Testnachricht."


def test_invalid_contact_data_is_rejected(api):
    res = api.post("/api/public/contact", json={
        "name": "", "email": "keine-email", "message": "",
    })
    assert res.status_code == 400
