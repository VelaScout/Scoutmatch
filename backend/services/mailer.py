"""Lokaler Mock-Mailer für die Entwicklungsumgebung.

Es ist bewusst KEIN echter E-Mail-Versand angebunden – das würde echte
SMTP-Zugangsdaten oder einen API-Key eines E-Mail-Anbieters erfordern, und
solche Secrets dürfen laut Vorgabe nicht ins Repository. Stattdessen werden
"gesendete" E-Mails in der Tabelle email_outbox gespeichert und zusätzlich in
die Konsole geloggt.

Admins können den Postausgang über GET /api/admin/outbox einsehen, um z. B.
den Verifizierungs- oder Passwort-Reset-Link eines Test-Accounts zu finden
und den kompletten Flow lokal durchzuklicken.

Für einen echten Betrieb müsste hier ein richtiger Provider (z. B. Resend,
Brevo oder ein SMTP-Anbieter) angebunden werden – das ist bewusst NICHT Teil
dieser lokalen MVP-Version (siehe README, Abschnitt "Production Deployment").
"""
from datetime import datetime, timezone

EMAIL_TYPES = ("email_verification", "password_reset", "sonstiges")


def send_mail(db, to, subject, body, email_type="sonstiges"):
    """Schreibt die "gesendete" E-Mail in email_outbox (gleiche DB-Verbindung
    wie der Aufrufer – der Aufrufer committet). Zusätzlich Konsolen-Log für
    schnelles lokales Debugging ohne Admin-UI."""
    if email_type not in EMAIL_TYPES:
        email_type = "sonstiges"
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    db.execute(
        """INSERT INTO email_outbox (recipient, subject, body, email_type, status, created_at, sent_at)
           VALUES (?, ?, ?, ?, 'gesendet', ?, ?)""",
        (to, subject, body, email_type, now, now),
    )
    print(f"\n[MOCK-MAILER] An: {to} | Betreff: {subject}\n{body}\n")


def read_outbox(db, limit=50):
    rows = db.execute(
        "SELECT id, recipient, subject, body, email_type, status, created_at, sent_at "
        "FROM email_outbox ORDER BY created_at DESC LIMIT ?",
        (limit,),
    ).fetchall()
    return [dict(r) for r in rows]
