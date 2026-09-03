"""Zentrale Konfiguration. Alle Werte kommen aus Umgebungsvariablen (.env),
niemals als Klartext-Secrets im Code (siehe README, Abschnitt "Production
Deployment" für die produktionsrelevanten Einstellungen)."""
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent


class Config:
    SECRET_KEY = os.environ.get("SECRET_KEY", "dev-only-insecure-key")

    # Pfad relativ zum Projektverzeichnis (siehe backend/database/connection.py).
    DATABASE_PATH = os.environ.get("DATABASE_PATH", "instance/scoutmatch.db")

    UPLOAD_FOLDER = str(BASE_DIR / "uploads")
    MAX_CONTENT_LENGTH = int(os.environ.get("MAX_UPLOAD_BYTES", 5 * 1024 * 1024))

    # Server-seitige Sessions (Flask-Session, Filesystem-Backend). Die Cookie
    # enthält nur eine zufällige Session-ID, keine Nutzerdaten.
    SESSION_TYPE = "filesystem"
    SESSION_FILE_DIR = str(BASE_DIR / "instance" / "flask_session")
    SESSION_PERMANENT = True
    PERMANENT_SESSION_LIFETIME = 60 * 60 * 8  # 8 Stunden
    SESSION_COOKIE_NAME = "scoutmatch_session"
    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = "Lax"
    # Nur lokal per http:// – daher standardmäßig False. Bei echtem Deployment
    # über https:// MUSS SESSION_COOKIE_SECURE=true gesetzt werden (.env).
    SESSION_COOKIE_SECURE = os.environ.get("SESSION_COOKIE_SECURE", "false").lower() == "true"

    DEBUG = os.environ.get("FLASK_DEBUG", "true").lower() == "true"


class TestConfig(Config):
    """Für pytest: isolierte DB/Session pro Testlauf, keine Rate-Limits, keine
    Vermischung mit echten Entwicklungsdaten. DATABASE_PATH/SESSION_FILE_DIR
    werden von der conftest.py-Fixture pro Test überschrieben (tmp_path)."""
    TESTING = True
    DEBUG = False
    RATELIMIT_ENABLED = False
