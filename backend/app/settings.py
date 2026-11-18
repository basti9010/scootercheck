from __future__ import annotations

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


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


settings = Settings()
