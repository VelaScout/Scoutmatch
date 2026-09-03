"""Öffentliche, nicht authentifizierte Endpunkte (z. B. das Kontaktformular)."""
from flask import Blueprint, jsonify, request

from backend.database.connection import get_db
from backend.extensions import limiter
from backend.services.mailer import send_mail
from backend.utils.security import clean_str, is_valid_email

bp = Blueprint("public", __name__, url_prefix="/api/public")

SUPPORT_INBOX = "[SUPPORT-E-MAIL EINTRAGEN]"
DEFAULT_SUBJECT = "Kontaktanfrage über die Website"


@bp.post("/contact")
@limiter.limit("5 per hour")
def contact():
    data = request.get_json(silent=True) or {}
    name = clean_str(data.get("name"), 150)
    email = clean_str(data.get("email"), 254)
    subject = clean_str(data.get("subject"), 200) or DEFAULT_SUBJECT
    message = clean_str(data.get("message"), 2000)

    if not name or not is_valid_email(email) or not message:
        return jsonify(error="Bitte fülle alle Felder korrekt aus."), 400

    db = get_db()
    db.execute(
        "INSERT INTO contact_messages (name, email, subject, message) VALUES (?, ?, ?, ?)",
        (name, email, subject, message),
    )
    send_mail(
        db,
        SUPPORT_INBOX,
        f"{subject} – von {name}",
        f"Von: {name} <{email}>\n\n{message}",
        email_type="sonstiges",
    )
    db.commit()
    return jsonify(ok=True)
