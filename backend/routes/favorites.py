"""Favoriten & Favoritenlisten – ausschließlich für eingeloggte Vereinsaccounts.

Jede Anfrage prüft serverseitig, dass der Favorit auch wirklich dem
angefragenden Verein gehört (Ownership-Check) – ein Verein kann nie die
Favoriten eines anderen Vereins lesen oder verändern.
"""
from flask import Blueprint, jsonify, request, session

from backend.database.connection import get_db
from backend.routes.players import PUBLIC_FIELDS, _age
from backend.utils.security import clean_str, csrf_protect, role_required

bp = Blueprint("favorites", __name__, url_prefix="/api/favorites")


def _own_club_id(db):
    row = db.execute("SELECT id FROM club_profiles WHERE user_id = ?", (session["user_id"],)).fetchone()
    return row["id"] if row else None


@bp.get("")
@role_required("club")
def list_favorites():
    db = get_db()
    club_id = _own_club_id(db)
    if not club_id:
        return jsonify(error="Kein Vereinsprofil gefunden."), 404

    list_filter = clean_str(request.args.get("list"), 120)
    sql = f"""
        SELECT f.id AS favorite_id, f.list_name, f.notiz, f.created_at, {PUBLIC_FIELDS.replace('id', 'p.id')}, p.geburtsdatum
        FROM favorites f JOIN player_profiles p ON p.id = f.player_id
        WHERE f.club_id = ?
    """
    params = [club_id]
    if list_filter:
        sql += " AND f.list_name = ?"
        params.append(list_filter)
    sql += " ORDER BY f.created_at DESC"

    rows = db.execute(sql, params).fetchall()
    favorites = []
    for row in rows:
        d = dict(row)
        d["alter"] = _age(d.pop("geburtsdatum"))
        favorites.append(d)

    return jsonify(favorites=favorites, count=len(favorites))


@bp.get("/lists")
@role_required("club")
def list_names():
    db = get_db()
    club_id = _own_club_id(db)
    if not club_id:
        return jsonify(error="Kein Vereinsprofil gefunden."), 404
    rows = db.execute(
        "SELECT list_name, COUNT(*) AS count FROM favorites WHERE club_id = ? GROUP BY list_name ORDER BY list_name",
        (club_id,),
    ).fetchall()
    return jsonify(lists=[dict(r) for r in rows])


@bp.post("")
@role_required("club")
def add_favorite():
    csrf_err = csrf_protect()
    if csrf_err:
        return csrf_err

    data = request.get_json(silent=True) or {}
    db = get_db()
    club_id = _own_club_id(db)
    if not club_id:
        return jsonify(error="Kein Vereinsprofil gefunden."), 404

    player_id = data.get("player_id")
    if not isinstance(player_id, int):
        return jsonify(error="player_id fehlt oder ungültig."), 400

    player = db.execute("SELECT id FROM player_profiles WHERE id = ? AND profil_sichtbar = 1", (player_id,)).fetchone()
    if not player:
        return jsonify(error="Spielerprofil nicht gefunden."), 404

    list_name = clean_str(data.get("list_name"), 120) or "Favoriten"
    notiz = clean_str(data.get("notiz"), 500)

    try:
        cur = db.execute(
            "INSERT INTO favorites (club_id, player_id, list_name, notiz) VALUES (?, ?, ?, ?)",
            (club_id, player_id, list_name, notiz),
        )
        db.commit()
    except db.IntegrityError:
        return jsonify(error="Dieser Spieler ist bereits in dieser Liste."), 409

    return jsonify(ok=True, favorite_id=cur.lastrowid), 201


@bp.put("/<int:favorite_id>")
@role_required("club")
def update_favorite(favorite_id):
    csrf_err = csrf_protect()
    if csrf_err:
        return csrf_err

    db = get_db()
    club_id = _own_club_id(db)
    owned = db.execute("SELECT id FROM favorites WHERE id = ? AND club_id = ?", (favorite_id, club_id)).fetchone()
    if not owned:
        return jsonify(error="Favorit nicht gefunden."), 404

    data = request.get_json(silent=True) or {}
    fields = {}
    if "notiz" in data:
        fields["notiz"] = clean_str(data.get("notiz"), 500)
    if "list_name" in data:
        fields["list_name"] = clean_str(data.get("list_name"), 120) or "Favoriten"
    if not fields:
        return jsonify(error="Keine Änderungen übermittelt."), 400

    set_clause = ", ".join(f"{k} = ?" for k in fields)
    db.execute(f"UPDATE favorites SET {set_clause} WHERE id = ?", list(fields.values()) + [favorite_id])
    db.commit()
    return jsonify(ok=True)


@bp.delete("/<int:favorite_id>")
@role_required("club")
def remove_favorite(favorite_id):
    csrf_err = csrf_protect()
    if csrf_err:
        return csrf_err

    db = get_db()
    club_id = _own_club_id(db)
    result = db.execute("DELETE FROM favorites WHERE id = ? AND club_id = ?", (favorite_id, club_id))
    db.commit()
    if result.rowcount == 0:
        return jsonify(error="Favorit nicht gefunden."), 404
    return jsonify(ok=True)


@bp.put("/lists/<path:old_name>")
@role_required("club")
def rename_list(old_name):
    csrf_err = csrf_protect()
    if csrf_err:
        return csrf_err

    data = request.get_json(silent=True) or {}
    new_name = clean_str(data.get("new_name"), 120)
    if not new_name:
        return jsonify(error="Neuer Listenname fehlt."), 400

    db = get_db()
    club_id = _own_club_id(db)
    db.execute(
        "UPDATE favorites SET list_name = ? WHERE club_id = ? AND list_name = ?",
        (new_name, club_id, old_name),
    )
    db.commit()
    return jsonify(ok=True)


@bp.delete("/lists/<path:name>")
@role_required("club")
def delete_list(name):
    csrf_err = csrf_protect()
    if csrf_err:
        return csrf_err

    db = get_db()
    club_id = _own_club_id(db)
    db.execute("DELETE FROM favorites WHERE club_id = ? AND list_name = ?", (club_id, name))
    db.commit()
    return jsonify(ok=True)
