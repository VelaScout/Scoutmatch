"""Spielerprofile: Suche (Vereine), Ansicht (Vereine), eigenes Profil (Spieler).

Datenschutz-Trennung (Block 27): die öffentliche/Club-Sicht gibt NIE
Login-E-Mail, Passwort-Hash oder interne Felder aus – nur die dafür
vorgesehenen sportlichen Felder.
"""
from datetime import date, datetime, timezone

from flask import Blueprint, jsonify, request, session

from backend.database.connection import get_db
from backend.models.constants import PLAYER_PUBLIC_FIELDS as PUBLIC_FIELDS
from backend.models.constants import VERIFICATION_TYPES
from backend.utils.security import clean_int, clean_str, csrf_protect, role_required

bp = Blueprint("players", __name__, url_prefix="/api/players")


def _age(geburtsdatum):
    if not geburtsdatum:
        return None
    try:
        y, m, d = (int(x) for x in geburtsdatum.split("-"))
        born = date(y, m, d)
    except (ValueError, AttributeError):
        return None
    today = date.today()
    return today.year - born.year - ((today.month, today.day) < (born.month, born.day))


def _videos_for(db, player_id):
    rows = db.execute(
        "SELECT id, titel, video_url FROM player_videos WHERE player_id = ? ORDER BY created_at DESC",
        (player_id,),
    ).fetchall()
    return [dict(r) for r in rows]


def _public_player_dict(row, db):
    d = dict(row)
    d["alter"] = _age(d.get("geburtsdatum"))
    del d["geburtsdatum"]  # exaktes Geburtsdatum bleibt privat, nur Alter ist öffentlich
    d["is_demo"] = bool(d.get("is_demo"))

    stats = db.execute(
        "SELECT saison, einsaetze, startelf, minuten, tore, assists, verification_status "
        "FROM player_stats WHERE player_id = ? ORDER BY saison DESC",
        (d["id"],),
    ).fetchall()
    d["statistiken"] = [dict(s) for s in stats]
    d["videos"] = _videos_for(db, d["id"])

    verifications = db.execute(
        "SELECT verification_type, status FROM verifications "
        "WHERE user_id = (SELECT user_id FROM player_profiles WHERE id = ?)",
        (d["id"],),
    ).fetchall()
    d["verifizierung"] = {v["verification_type"]: v["status"] for v in verifications}
    return d


SORT_OPTIONS = {
    "neueste": lambda p: p.get("id") or 0,
    "alter_auf": lambda p: (p.get("alter") is None, p.get("alter") or 0),
    "alter_ab": lambda p: (p.get("alter") is None, -(p.get("alter") or 0)),
    "tore_ab": lambda p: -((p["statistiken"][0]["tore"]) if p["statistiken"] else 0),
    "name_auf": lambda p: ((p.get("nachname") or "").lower(), (p.get("vorname") or "").lower()),
}


@bp.get("/search")
@role_required("club")
def search():
    db = get_db()

    club = db.execute(
        "SELECT verification_status FROM club_profiles WHERE user_id = ?", (session["user_id"],)
    ).fetchone()
    if not club or club["verification_status"] != "verified":
        return jsonify(error="Dein Vereinskonto muss zuerst von einem Admin freigegeben werden."), 403

    where = ["profil_sichtbar = 1"]
    params = []

    position = clean_str(request.args.get("position"), 60)
    if position:
        where.append("hauptposition = ?")
        params.append(position)

    nebenposition = clean_str(request.args.get("nebenposition"), 60)
    if nebenposition:
        where.append("nebenposition LIKE ?")
        params.append(f"%{nebenposition}%")

    liga = clean_str(request.args.get("liga"), 120)
    if liga:
        where.append("liga LIKE ?")
        params.append(f"%{liga}%")

    region = clean_str(request.args.get("region"), 120)
    if region:
        where.append("wohnort LIKE ?")
        params.append(f"%{region}%")

    fuss = clean_str(request.args.get("fuss"), 20)
    if fuss:
        where.append("starker_fuss = ?")
        params.append(fuss)

    vertrag = clean_str(request.args.get("vertrag"), 40)
    if vertrag:
        where.append("vertragsstatus = ?")
        params.append(vertrag)

    verfuegbar_ab = clean_str(request.args.get("verfuegbarAb"), 20)
    if verfuegbar_ab:
        where.append("verfuegbar_ab = ?")
        params.append(verfuegbar_ab)

    groesse_von = clean_int(request.args.get("groesseVon"), 100, 230)
    if groesse_von is not None:
        where.append("groesse >= ?")
        params.append(groesse_von)

    groesse_bis = clean_int(request.args.get("groesseBis"), 100, 230)
    if groesse_bis is not None:
        where.append("groesse <= ?")
        params.append(groesse_bis)

    # Vertragsende ist als ISO-Datum (YYYY-MM-DD) gespeichert, daher ist ein
    # einfacher String-Vergleich hier korrekt und sortiert wie ein Datum.
    vertragsende_bis = clean_str(request.args.get("vertragsendeBis"), 20)
    if vertragsende_bis:
        where.append("vertragsende IS NOT NULL AND vertragsende <= ?")
        params.append(vertragsende_bis)

    sql = f"SELECT {PUBLIC_FIELDS}, geburtsdatum FROM player_profiles WHERE " + " AND ".join(where)
    rows = db.execute(sql, params).fetchall()

    alter_von = clean_int(request.args.get("alterVon"), 14, 60)
    alter_bis = clean_int(request.args.get("alterBis"), 14, 60)
    nur_verifiziert = request.args.get("nurVerifiziert") in ("1", "true")
    tore_min = clean_int(request.args.get("toreMin"), 0, 200)
    assists_min = clean_int(request.args.get("assistsMin"), 0, 200)
    einsaetze_min = clean_int(request.args.get("einsaetzeMin"), 0, 60)

    results = []
    for row in rows:
        d = dict(row)
        d["is_demo"] = bool(d.get("is_demo"))
        alter = _age(d.get("geburtsdatum"))
        if alter_von is not None and (alter is None or alter < alter_von):
            continue
        if alter_bis is not None and (alter is None or alter > alter_bis):
            continue
        del d["geburtsdatum"]
        d["alter"] = alter

        stats = db.execute(
            "SELECT saison, einsaetze, startelf, minuten, tore, assists, verification_status "
            "FROM player_stats WHERE player_id = ? ORDER BY saison DESC",
            (d["id"],),
        ).fetchall()
        d["statistiken"] = [dict(s) for s in stats]
        latest = d["statistiken"][0] if d["statistiken"] else {}
        if tore_min is not None and (latest.get("tore") or 0) < tore_min:
            continue
        if assists_min is not None and (latest.get("assists") or 0) < assists_min:
            continue
        if einsaetze_min is not None and (latest.get("einsaetze") or 0) < einsaetze_min:
            continue

        v = db.execute(
            "SELECT verification_type, status FROM verifications "
            "WHERE user_id = (SELECT user_id FROM player_profiles WHERE id = ?)",
            (d["id"],),
        ).fetchall()
        verifizierung = {row2["verification_type"]: row2["status"] for row2 in v}
        if nur_verifiziert and any(verifizierung.get(t) != "verifiziert" for t in VERIFICATION_TYPES):
            continue
        d["verifizierung"] = verifizierung
        results.append(d)

    sort_key = SORT_OPTIONS.get(request.args.get("sort"), SORT_OPTIONS["neueste"])
    results.sort(key=sort_key)

    total = len(results)
    page = clean_int(request.args.get("page"), 1, 10_000) or 1
    per_page = clean_int(request.args.get("perPage"), 1, 100) or 50
    start = (page - 1) * per_page
    page_results = results[start:start + per_page]

    return jsonify(
        players=page_results,
        count=len(page_results),
        total=total,
        page=page,
        per_page=per_page,
    )


@bp.get("/me")
@role_required("player")
def get_me():
    db = get_db()
    row = db.execute("SELECT * FROM player_profiles WHERE user_id = ?", (session["user_id"],)).fetchone()
    if not row:
        return jsonify(error="Kein Spielerprofil gefunden."), 404
    d = dict(row)
    d["alter"] = _age(d.get("geburtsdatum"))
    d["is_demo"] = bool(d.get("is_demo"))
    stats = db.execute(
        "SELECT saison, einsaetze, startelf, minuten, tore, assists, verification_status "
        "FROM player_stats WHERE player_id = ? ORDER BY saison DESC",
        (d["id"],),
    ).fetchall()
    d["statistiken"] = [dict(s) for s in stats]
    d["videos"] = _videos_for(db, d["id"])
    verifications = db.execute(
        "SELECT verification_type, status FROM verifications WHERE user_id = ?",
        (session["user_id"],),
    ).fetchall()
    d["verifizierung"] = {v["verification_type"]: v["status"] for v in verifications}
    return jsonify(player=d)


UPDATABLE_FIELDS = (
    "vorname", "nachname", "geburtsdatum", "wohnort", "nationalitaet",
    "hauptposition", "nebenposition", "aktueller_verein", "liga",
    "starker_fuss", "vertragsstatus", "vertragsende", "verfuegbar_ab", "wechselstatus",
)


@bp.put("/me")
@role_required("player")
def update_me():
    csrf_err = csrf_protect()
    if csrf_err:
        return csrf_err

    data = request.get_json(silent=True) or {}
    db = get_db()
    player = db.execute("SELECT id FROM player_profiles WHERE user_id = ?", (session["user_id"],)).fetchone()
    if not player:
        return jsonify(error="Kein Spielerprofil gefunden."), 404

    updates = {}
    for field in UPDATABLE_FIELDS:
        if field in data:
            updates[field] = clean_str(data.get(field), 200)

    if "groesse" in data:
        updates["groesse"] = clean_int(data.get("groesse"), 100, 230)
    if "gewicht" in data:
        updates["gewicht"] = clean_int(data.get("gewicht"), 30, 200)
    if "profil_sichtbar" in data:
        updates["profil_sichtbar"] = 1 if data.get("profil_sichtbar") else 0

    stat = data.get("statistik")
    has_stat = isinstance(stat, dict) and stat.get("saison")

    if not updates and not has_stat:
        return jsonify(error="Keine gültigen Felder übermittelt."), 400

    if updates:
        updates["updated_at"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
        set_clause = ", ".join(f"{k} = ?" for k in updates)
        params = list(updates.values()) + [session["user_id"]]
        db.execute(f"UPDATE player_profiles SET {set_clause} WHERE user_id = ?", params)

    # Optionale Leistungsdaten für eine Saison (upsert)
    if has_stat:
        saison = clean_str(stat.get("saison"), 20)
        db.execute(
            """INSERT INTO player_stats (player_id, saison, einsaetze, startelf, minuten, tore, assists, verification_status)
               VALUES (?, ?, ?, ?, ?, ?, ?, 'selbst_angegeben')
               ON CONFLICT(player_id, saison) DO UPDATE SET
                 einsaetze=excluded.einsaetze, startelf=excluded.startelf, minuten=excluded.minuten,
                 tore=excluded.tore, assists=excluded.assists""",
            (
                player["id"], saison,
                clean_int(stat.get("einsaetze"), 0, 60) or 0,
                clean_int(stat.get("startelf"), 0, 60) or 0,
                clean_int(stat.get("minuten"), 0, 6000) or 0,
                clean_int(stat.get("tore"), 0, 200) or 0,
                clean_int(stat.get("assists"), 0, 200) or 0,
            ),
        )

    db.commit()
    return jsonify(ok=True)


MAX_VIDEOS_PER_PLAYER = 10


def _own_player_id(db):
    row = db.execute("SELECT id FROM player_profiles WHERE user_id = ?", (session["user_id"],)).fetchone()
    return row["id"] if row else None


@bp.post("/me/videos")
@role_required("player")
def add_video():
    csrf_err = csrf_protect()
    if csrf_err:
        return csrf_err

    db = get_db()
    player_id = _own_player_id(db)
    if not player_id:
        return jsonify(error="Kein Spielerprofil gefunden."), 404

    data = request.get_json(silent=True) or {}
    titel = clean_str(data.get("titel"), 150)
    video_url = clean_str(data.get("video_url"), 500)
    if not titel or not video_url:
        return jsonify(error="Bitte gib einen Titel und einen Video-Link an."), 400
    if not video_url.startswith(("http://", "https://")):
        return jsonify(error="Der Video-Link muss mit http:// oder https:// beginnen."), 400

    count = db.execute("SELECT COUNT(*) AS c FROM player_videos WHERE player_id = ?", (player_id,)).fetchone()["c"]
    if count >= MAX_VIDEOS_PER_PLAYER:
        return jsonify(error=f"Es können maximal {MAX_VIDEOS_PER_PLAYER} Videos hinterlegt werden."), 400

    cur = db.execute(
        "INSERT INTO player_videos (player_id, titel, video_url) VALUES (?, ?, ?)",
        (player_id, titel, video_url),
    )
    db.commit()
    return jsonify(ok=True, id=cur.lastrowid), 201


@bp.delete("/me/videos/<int:video_id>")
@role_required("player")
def delete_video(video_id):
    csrf_err = csrf_protect()
    if csrf_err:
        return csrf_err

    db = get_db()
    player_id = _own_player_id(db)
    result = db.execute(
        "DELETE FROM player_videos WHERE id = ? AND player_id = ?", (video_id, player_id)
    )
    db.commit()
    if result.rowcount == 0:
        return jsonify(error="Video nicht gefunden."), 404
    return jsonify(ok=True)


@bp.post("/me/verification/<verification_type>/request")
@role_required("player")
def request_verification(verification_type):
    csrf_err = csrf_protect()
    if csrf_err:
        return csrf_err
    if verification_type not in VERIFICATION_TYPES:
        return jsonify(error="Ungültiger Verifizierungstyp."), 400

    db = get_db()
    row = db.execute(
        "SELECT status FROM verifications WHERE user_id = ? AND verification_type = ?",
        (session["user_id"], verification_type),
    ).fetchone()
    if row and row["status"] in ("pruefung_ausstehend", "verifiziert"):
        return jsonify(error="Für diese Kategorie liegt bereits eine Prüfung vor."), 400

    db.execute(
        """INSERT INTO verifications (user_id, verification_type, status)
           VALUES (?, ?, 'pruefung_ausstehend')
           ON CONFLICT(user_id, verification_type) DO UPDATE SET status = 'pruefung_ausstehend'""",
        (session["user_id"], verification_type),
    )
    db.commit()
    return jsonify(ok=True)


@bp.get("/<int:player_id>")
@role_required("club", "player", "admin")
def get_player(player_id):
    db = get_db()
    row = db.execute(
        f"SELECT {PUBLIC_FIELDS} FROM player_profiles WHERE id = ? AND profil_sichtbar = 1", (player_id,)
    ).fetchone()
    if not row:
        return jsonify(error="Profil nicht gefunden."), 404
    return jsonify(player=_public_player_dict(row, db))
