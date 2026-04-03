from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


class ConfigError(ValueError):
    pass


def _env_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _env_int(name: str, default: int) -> int:
    value = os.getenv(name)
    if value is None or not value.strip():
        return default
    return int(value)


@dataclass(frozen=True)
class Settings:
    root_dir: Path
    data_dir: Path
    db_path: Path
    admin_password: str
    host: str
    port: int
    domain: str
    retention_hours: int
    cleanup_addresses: bool


def _required_env(name: str) -> str:
    value = os.getenv(name)
    if value is None or not value.strip():
        raise ConfigError(f"缺少必填环境变量: {name}")
    return value


def load_settings() -> Settings:
    root_dir = Path(os.getenv("TEMP_MAIL_ROOT", "/opt/temp-mail"))
    data_dir = Path(os.getenv("TEMP_MAIL_DATA_DIR", str(root_dir / "data")))
    db_path = Path(os.getenv("TEMP_MAIL_DB_PATH", str(data_dir / "temp_mail.db")))

    domain = os.getenv("TEMP_MAIL_DOMAIN", "temp-mail.example.com")

    return Settings(
        root_dir=root_dir,
        data_dir=data_dir,
        db_path=db_path,
        admin_password=_required_env("TEMP_MAIL_ADMIN_PASSWORD"),
        host=os.getenv("TEMP_MAIL_HOST", "0.0.0.0"),
        port=_env_int("TEMP_MAIL_PORT", 8000),
        domain=domain,
        retention_hours=_env_int("TEMP_MAIL_RETENTION_HOURS", 1),
        cleanup_addresses=_env_bool("TEMP_MAIL_CLEANUP_ADDRESSES", True),
    )


settings = load_settings()
