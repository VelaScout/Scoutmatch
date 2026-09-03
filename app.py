"""ScoutMatch – lokaler Entwicklungsserver (Flask).

WICHTIG: Dieser Server ist ausschließlich für lokale Entwicklung/Tests
gedacht (siehe README, Abschnitt "Production Deployment" für alles, was für
einen echten Betrieb zusätzlich nötig wäre).

Dies ist bewusst nur ein dünner Einstiegspunkt: die eigentliche
Anwendungslogik liegt in backend/ (Datenbank, Routen, Services, Utils),
sauber nach Zuständigkeit getrennt (siehe README, Abschnitt "Projektstruktur").
"""
import os
from pathlib import Path

from dotenv import load_dotenv
from flask import Flask, request, send_from_directory
from flask_session import Session

from backend.database.connection import init_db
from backend.extensions import limiter
from config import Config

BASE_DIR = Path(__file__).resolve().parent
load_dotenv(BASE_DIR / ".env")


def create_app(config_class=Config, config_overrides=None):
    app = Flask(
        __name__,
        static_folder=str(BASE_DIR / "public"),
        static_url_path="",
    )
    app.config.from_object(config_class)
    if config_overrides:
        app.config.update(config_overrides)

    Path(app.config["SESSION_FILE_DIR"]).mkdir(parents=True, exist_ok=True)
    Session(app)
    limiter.init_app(app)
    init_db(app)

    from backend.routes.admin import bp as admin_bp
    from backend.routes.auth import bp as auth_bp
    from backend.routes.contact import bp as contact_bp
    from backend.routes.favorites import bp as favorites_bp
    from backend.routes.players import bp as players_bp
    from backend.routes.public import bp as public_bp
    from backend.routes.uploads import bp as uploads_bp

    app.register_blueprint(auth_bp)
    app.register_blueprint(players_bp)
    app.register_blueprint(favorites_bp)
    app.register_blueprint(uploads_bp)
    app.register_blueprint(contact_bp)
    app.register_blueprint(admin_bp)
    app.register_blueprint(public_bp)

    @app.after_request
    def set_security_headers(resp):
        resp.headers["X-Content-Type-Options"] = "nosniff"
        resp.headers["X-Frame-Options"] = "DENY"
        resp.headers["Referrer-Policy"] = "same-origin"
        return resp

    @app.errorhandler(404)
    def not_found(_e):
        if request.path.startswith("/api/"):
            from flask import jsonify
            return jsonify(error="Nicht gefunden."), 404
        return send_from_directory(app.static_folder, "index.html"), 404

    @app.route("/")
    def root():
        return send_from_directory(app.static_folder, "index.html")

    return app


if __name__ == "__main__":
    app = create_app()
    port = int(os.environ.get("PORT", 5001))
    print(f"\nScoutMatch läuft lokal auf: http://127.0.0.1:{port}\n")
    app.run(host="127.0.0.1", port=port, debug=app.config["DEBUG"])
