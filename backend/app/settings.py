from __future__ import annotations

import os
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

# Known insecure field defaults — production must override via env / EnvironmentFile.
_INSECURE_JWT_SECRETS = frozenset({"", "change-me-in-production", "change-me"})
_INSECURE_ADMIN_PASSWORDS = frozenset({"", "change-me"})


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "ScooterCheck Auth"
    database_path: str = "data/scootercheck.db"
    jwt_secret: str = "change-me-in-production"
    jwt_algorithm: str = "HS256"
    jwt_expire_hours: int = 24 * 14
    admin_email: str = "admin@example.com"
    admin_password: str = "change-me"
    admin_name: str = "Admin"
    cors_origins: str = "*"

    def db_path(self) -> Path:
        return Path(self.database_path).expanduser().resolve()

    def assert_secure_configuration(self) -> None:
        """Fail closed unless secrets are set, or local/dev explicitly opts in.

        Set ALLOW_INSECURE_AUTH_DEFAULTS=1 only for local scratch / unit tests.
        Production systemd uses EnvironmentFile=/opt/scootercheck/.env — missing
        JWT_SECRET / ADMIN_PASSWORD must refuse to start (no silent weak defaults).
        """
        allow = os.getenv("ALLOW_INSECURE_AUTH_DEFAULTS", "").strip().lower() in {
            "1",
            "true",
            "yes",
        }
        weak_jwt = self.jwt_secret.strip() in _INSECURE_JWT_SECRETS
        weak_admin = self.admin_password.strip() in _INSECURE_ADMIN_PASSWORDS
        if allow:
            return
        problems: list[str] = []
        if weak_jwt:
            problems.append("JWT_SECRET is missing or still an insecure default")
        if weak_admin:
            problems.append("ADMIN_PASSWORD is missing or still an insecure default")
        if problems:
            raise RuntimeError(
                "ScooterCheck Auth refusing to start (fail-closed): "
                + "; ".join(problems)
                + ". Set strong values in the EnvironmentFile, or "
                "ALLOW_INSECURE_AUTH_DEFAULTS=1 for local-only."
            )


settings = Settings()
