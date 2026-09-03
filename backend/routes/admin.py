"""Admin-Bereich: Nutzerverwaltung, Vereins- und Spieler-Verifizierung.

Jede Route ist über role_required("admin") geschützt – der Schutz liegt
serverseitig auf der Route selbst, nicht in der Sichtbarkeit eines Menüs.
Es gibt bewusst keine öffentliche Admin-Registrierung; Admin-Konten werden
lokal über create_admin.py angelegt.

Jede sicherheitsrelevante Änderung (Sperren, Freigeben, Verifizieren, Profil
deaktivieren, Löschen) schreibt zusätzlich einen Eintrag in admin_audit_log.
"""
from datetime import datetime, timezone

from flask import Blueprint, jsonify, request, session

from backend.database.connection import get_db
from backend.models.constants import CLUB_STATUSES, VERIFICATION_STATUSES, VERIFICATION_TYPES
from backend.services.audit import log_admin_action as _log_action
from backend.services.mailer import read_outbox
from backend.utils.security import clean_str, csrf_protect, role_required

bp = Blueprint("admin", __name__, url_prefix="/api/admin")


@bp.get("/users")
@role_required("admin")
def list_users():
    db = get_db()
    rows = db.execute(
        """SELECT u.id, u.email, u.role, u.email_verified, u.is_locked, u.created_at, u.last_login_at,
                  p.vorname, p.nachname, c.vereinsname
           FROM users u
           LEFT JOIN player_profiles p ON p.user_id = u.id
           LEFT JOIN club_profiles c ON c.user_id = u.id
           ORDER BY u.created_at DESC"""
    ).fetchall()
    users = []
    for r in rows:
        d = dict(r)
        if d["role"] == "player":
            d["name"] = f"{d.pop('vorname') or ''} {d.pop('nachname') or ''}".strip()
            d.pop("vereinsname", None)
        elif d["role"] == "club":
            d["name"] = d.pop("vereinsname")
            d.pop("vorname", None)
            d.pop("nachname", None)
        else:
            d["name"] = None
            d.pop("vorname", None)
            d.pop("nachname", None)
            d.pop("vereinsname", None)
        users.append(d)
    return jsonify(users=users)


@bp.put("/users/<int:user_id>/lock")
@role_required("admin")
def set_lock(user_id):
    csrf_err = csrf_protect()
    if csrf_err:
        return csrf_err
    if user_id == session["user_id"]:
        return jsonify(error="Du kannst dein eigenes Konto nicht sperren."), 400

    data = request.get_json(silent=True) or {}
    locked = bool(data.get("locked"))

    db = get_db()
    result = db.execute("UPDATE users SET is_locked = ? WHERE id = ?", (1 if locked else 0, user_id))
    if result.rowcount == 0:
        db.rollback()
        return jsonify(error="Nutzer nicht gefunden."), 404
    _log_action(db, session["user_id"], "user_locked" if locked else "user_unlocked", "user", user_id)
    db.commit()
    return jsonify(ok=True)


@bp.delete("/users/<int:user_id>")
@role_required("admin")
def delete_user(user_id):
    csrf_err = csrf_protect()
    if csrf_err:
        return csrf_err
    if user_id == session["user_id"]:
        return jsonify(error="Du kannst dein eigenes Konto nicht löschen."), 400

    db = get_db()
    result = db.execute("DELETE FROM users WHERE id = ?", (user_id,))
    if result.rowcount == 0:
        db.rollback()
        return jsonify(error="Nutzer nicht gefunden."), 404
    _log_action(db, session["user_id"], "user_deleted", "user", user_id)
    db.commit()
    return jsonify(ok=True)


@bp.get("/clubs")
@role_required("admin")
def list_clubs():
    db = get_db()
    rows = db.execute(
        """SELECT c.id, c.vereinsname, c.liga, c.ort, c.website, c.verification_status,
                  c.ansprechpartner_vorname, c.ansprechpartner_nachname, c.funktion, c.created_at,
                  u.id AS user_id, u.email, u.is_locked
           FROM club_profiles c JOIN users u ON u.id = c.user_id
           ORDER BY c.created_at DESC"""
    ).fetchall()
    return jsonify(clubs=[dict(r) for r in rows])


@bp.put("/clubs/<int:club_id>/verification")
@role_required("admin")
def set_club_verification(club_id):
    csrf_err = csrf_protect()
    if csrf_err:
        return csrf_err

    data = request.get_json(silent=True) or {}
    status = data.get("status")
    if status not in CLUB_STATUSES:
        return jsonify(error="Ungültiger Status."), 400

    db = get_db()
    result = db.execute(
        "UPDATE club_profiles SET verification_status = ?, updated_at = datetime('now') WHERE id = ?",
        (status, club_id),
    )
    if result.rowcount == 0:
        db.rollback()
        return jsonify(error="Verein nicht gefunden."), 404

    action = {"verified": "club_approved", "rejected": "club_rejected", "pending": "club_set_pending"}[status]
    _log_action(db, session["user_id"], action, "club", club_id)
    db.commit()
    return jsonify(ok=True)


@bp.get("/players")
@role_required("admin")
def list_players():
    db = get_db()
    rows = db.execute(
        """SELECT p.id, p.vorname, p.nachname, p.aktueller_verein, p.liga, p.profil_sichtbar, p.created_at,
                  u.id AS user_id, u.email, u.is_locked
           FROM player_profiles p JOIN users u ON u.id = p.user_id
           ORDER BY p.created_at DESC"""
    ).fetchall()
    players = []
    for r in rows:
        d = dict(r)
        v = db.execute(
            "SELECT verification_type, status FROM verifications WHERE user_id = ?", (d["user_id"],)
        ).fetchall()
        d["verifizierung"] = {row["verification_type"]: row["status"] for row in v}
        players.append(d)
    return jsonify(players=players)


@bp.put("/players/<int:player_id>/visibility")
@role_required("admin")
def set_player_visibility(player_id):
    """Deaktiviert/aktiviert ein Spielerprofil (unabhängig von der eigenen
    Sichtbarkeits-Einstellung des Spielers). Anders als das Löschen bleibt
    das Konto dabei erhalten – es ist nur für Vereine nicht mehr auffindbar."""
    csrf_err = csrf_protect()
    if csrf_err:
        return csrf_err

    data = request.get_json(silent=True) or {}
    sichtbar = bool(data.get("sichtbar"))

    db = get_db()
    result = db.execute(
        "UPDATE player_profiles SET profil_sichtbar = ? WHERE id = ?", (1 if sichtbar else 0, player_id)
    )
    if result.rowcount == 0:
        db.rollback()
        return jsonify(error="Spieler nicht gefunden."), 404
    _log_action(
        db, session["user_id"], "player_activated" if sichtbar else "player_deactivated", "player", player_id
    )
    db.commit()
    return jsonify(ok=True)


@bp.put("/players/<int:player_id>/verification")
@role_required("admin")
def set_player_verification(player_id):
    csrf_err = csrf_protect()
    if csrf_err:
        return csrf_err

    data = request.get_json(silent=True) or {}
    verification_type = data.get("verification_type")
    status = data.get("status")
    if verification_type not in VERIFICATION_TYPES or status not in VERIFICATION_STATUSES:
        return jsonify(error="Ungültiger Verifizierungstyp oder Status."), 400

    db = get_db()
    player = db.execute("SELECT user_id FROM player_profiles WHERE id = ?", (player_id,)).fetchone()
    if not player:
        return jsonify(error="Spieler nicht gefunden."), 404

    now = datetime.now(timezone.utc).isoformat(timespec="seconds")

    db.execute(
        """INSERT INTO verifications (user_id, verification_type, status, reviewed_at, reviewed_by)
           VALUES (?, ?, ?, ?, ?)
           ON CONFLICT(user_id, verification_type) DO UPDATE SET
             status = excluded.status, reviewed_at = excluded.reviewed_at, reviewed_by = excluded.reviewed_by""",
        (player["user_id"], verification_type, status, now, session["user_id"]),
    )
    action = "player_verified" if status == "verifiziert" else "player_verification_rejected" if status == "abgelehnt" else "player_verification_updated"
    _log_action(db, session["user_id"], action, "player", player_id, details=verification_type)
    db.commit()
    return jsonify(ok=True)


@bp.get("/outbox")
@role_required("admin")
def outbox():
    db = get_db()
    return jsonify(emails=read_outbox(db))


@bp.get("/audit-log")
@role_required("admin")
def audit_log():
    db = get_db()
    rows = db.execute(
        """SELECT a.id, a.action, a.target_type, a.target_id, a.details, a.created_at, u.email AS admin_email
           FROM admin_audit_log a JOIN users u ON u.id = a.admin_user_id
           ORDER BY a.created_at DESC LIMIT 200"""
    ).fetchall()
    return jsonify(entries=[dict(r) for r in rows])
