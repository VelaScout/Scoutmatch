"""Sicherer Profilbild-Upload.

- Erlaubte Endungen UND Inhalt (Magic Bytes) werden geprüft – nicht nur die
  vom Client gesendete Endung/MIME-Type (beides ist fälschbar).
- Dateiname wird niemals vom Client übernommen, sondern zufällig serverseitig
  erzeugt (verhindert Path-Traversal und Overwrite-Angriffe).
- Größe ist durch MAX_CONTENT_LENGTH global begrenzt (siehe app.py).
- Es werden ausschließlich Bilddateien akzeptiert – keine ausführbaren
  Dateien, keine .html/.svg (SVG kann Skripte enthalten und wird bewusst
  nicht erlaubt).
"""
import imghdr
import secrets
from pathlib import Path

from flask import Blueprint, current_app, jsonify, request, send_from_directory, session

from backend.database.connection import get_db
from backend.utils.security import csrf_protect, role_required

bp = Blueprint("uploads", __name__)

ALLOWED_EXTENSIONS = {"jpg", "jpeg", "png", "webp"}
# imghdr erkennt "webp" nicht in allen Python-Versionen zuverlässig als eigenen
# Typ – daher zusätzlich Signatur-Check für WebP (RIFF....WEBP).
ALLOWED_IMGHDR_TYPES = {"jpeg", "png"}


def _looks_like_webp(head: bytes) -> bool:
    return head[:4] == b"RIFF" and head[8:12] == b"WEBP"


def _upload_dir():
    d = Path(current_app.config["UPLOAD_FOLDER"])
    d.mkdir(parents=True, exist_ok=True)
    return d


@bp.post("/api/players/me/picture")
@role_required("player")
def upload_profile_picture():
    csrf_err = csrf_protect()
    if csrf_err:
        return csrf_err

    if "file" not in request.files:
        return jsonify(error="Keine Datei übermittelt."), 400

    file = request.files["file"]
    if not file or file.filename == "":
        return jsonify(error="Keine Datei ausgewählt."), 400

    orig_name = file.filename
    ext = orig_name.rsplit(".", 1)[-1].lower() if "." in orig_name else ""
    if ext not in ALLOWED_EXTENSIONS:
        return jsonify(error="Nur JPG, JPEG, PNG oder WebP sind erlaubt."), 400

    head = file.stream.read(64)
    file.stream.seek(0)
    detected = imghdr.what(None, head)
    is_valid_image = detected in ALLOWED_IMGHDR_TYPES or _looks_like_webp(head)
    if not is_valid_image:
        return jsonify(error="Die Datei ist kein gültiges Bild."), 400

    filename = f"{secrets.token_hex(16)}.{ext}"
    file.save(_upload_dir() / filename)

    db = get_db()
    db.execute(
        "UPDATE player_profiles SET profilbild = ? WHERE user_id = ?",
        (f"/uploads/{filename}", session["user_id"]),
    )
    db.commit()

    return jsonify(ok=True, profilbild=f"/uploads/{filename}")


@bp.get("/uploads/<path:filename>")
def serve_upload(filename):
    # send_from_directory schützt bereits vor Path-Traversal ("..").
    return send_from_directory(_upload_dir(), filename, max_age=3600)
