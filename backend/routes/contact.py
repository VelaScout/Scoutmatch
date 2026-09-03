"""Kontaktanfragen: Ein Verein kann bei einem Spieler Interesse anmelden.
Der Spieler sieht, wer wann angefragt hat, und kann annehmen oder ablehnen.

Datenschutz: Die private Kontakt-E-Mail des Spielers wird dem Verein erst
nach Annahme durch den Spieler angezeigt – vorher sieht der Verein nur den
Status seiner eigenen Anfrage.
"""
from flask import Blueprint, jsonify, request, session

from backend.database.connection import get_db
from backend.utils.security import clean_str, csrf_protect, role_required

bp = Blueprint("contact", __name__, url_prefix="/api/contact-requests")


def _own_club_id(db):
    row = db.execute("SELECT id FROM club_profiles WHERE user_id = ?", (session["user_id"],)).fetchone()
    return row["id"] if row else None


def _own_player_id(db):
    row = db.execute("SELECT id FROM player_profiles WHERE user_id = ?", (session["user_id"],)).fetchone()
    return row["id"] if row else None


@bp.post("")
@role_required("club")
def create_request():
    csrf_err = csrf_protect()
    if csrf_err:
        return csrf_err

    data = request.get_json(silent=True) or {}
    player_id = data.get("player_id")
    if not isinstance(player_id, int):
        return jsonify(error="player_id fehlt oder ungültig."), 400

    db = get_db()
    club_id = _own_club_id(db)
    if not club_id:
        return jsonify(error="Kein Vereinsprofil gefunden."), 404

    player = db.execute("SELECT id FROM player_profiles WHERE id = ? AND profil_sichtbar = 1", (player_id,)).fetchone()
    if not player:
        return jsonify(error="Spielerprofil nicht gefunden."), 404

    message = clean_str(data.get("message"), 500)

    try:
        cur = db.execute(
            "INSERT INTO contact_requests (club_id, player_id, message) VALUES (?, ?, ?)",
            (club_id, player_id, message),
        )
        db.commit()
    except db.IntegrityError:
        return jsonify(error="Du hast diesem Spieler bereits eine Anfrage gesendet."), 409

    return jsonify(ok=True, id=cur.lastrowid), 201


@bp.get("")
@role_required("club", "player")
def list_requests():
    db = get_db()

    if session["role"] == "club":
        club_id = _own_club_id(db)
        if not club_id:
            return jsonify(error="Kein Vereinsprofil gefunden."), 404
        rows = db.execute(
            """SELECT cr.id, cr.status, cr.message, cr.created_at,
                      p.id AS player_id, p.vorname, p.nachname, p.hauptposition, p.aktueller_verein,
                      CASE WHEN cr.status = 'accepted' THEN u.email ELSE NULL END AS player_email
               FROM contact_requests cr
               JOIN player_profiles p ON p.id = cr.player_id
               JOIN users u ON u.id = p.user_id
               WHERE cr.club_id = ?
               ORDER BY cr.created_at DESC""",
            (club_id,),
        ).fetchall()
        return jsonify(requests=[dict(r) for r in rows])

    player_id = _own_player_id(db)
    if not player_id:
        return jsonify(error="Kein Spielerprofil gefunden."), 404
    rows = db.execute(
        """SELECT cr.id, cr.status, cr.message, cr.created_at,
                  c.id AS club_id, c.vereinsname, c.liga, c.ort
           FROM contact_requests cr
           JOIN club_profiles c ON c.id = cr.club_id
           WHERE cr.player_id = ?
           ORDER BY cr.created_at DESC""",
        (player_id,),
    ).fetchall()
    return jsonify(requests=[dict(r) for r in rows])


@bp.put("/<int:request_id>")
@role_required("player")
def respond_to_request(request_id):
    csrf_err = csrf_protect()
    if csrf_err:
        return csrf_err

    data = request.get_json(silent=True) or {}
    status = data.get("status")
    if status not in ("accepted", "declined"):
        return jsonify(error="Ungültiger Status."), 400

    db = get_db()
    player_id = _own_player_id(db)
    owned = db.execute(
        "SELECT id FROM contact_requests WHERE id = ? AND player_id = ?", (request_id, player_id)
    ).fetchone()
    if not owned:
        return jsonify(error="Anfrage nicht gefunden."), 404

    db.execute("UPDATE contact_requests SET status = ? WHERE id = ?", (status, request_id))
    db.commit()
    return jsonify(ok=True)
