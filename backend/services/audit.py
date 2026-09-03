"""Protokollierung sicherheitsrelevanter Admin-Aktionen (admin_audit_log)."""


def log_admin_action(db, admin_user_id, action, target_type, target_id, details=None):
    db.execute(
        """INSERT INTO admin_audit_log (admin_user_id, action, target_type, target_id, details)
           VALUES (?, ?, ?, ?, ?)""",
        (admin_user_id, action, target_type, target_id, details),
    )
