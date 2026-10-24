"""Environment-based configuration for the Cellar Pi service.

Plain stdlib, no defaults for secrets. `GEMINI_API_KEY` in particular has no
fallback value: `Config.require_gemini_key()` raises if it is missing, and
the real entrypoint (main.py) calls that at import/startup time so a
misconfigured Pi fails loudly before it ever binds a port — never lazily at
the first `/recognize` request.

Never log a Config instance's gemini_api_key. Nothing in this module does.
"""
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

# pi/.env, next to this package. On the Pi, systemd exports it via
# EnvironmentFile= before the process starts; on a Mac running the mock or
# lab entrypoint nothing does, so without this loader the README's "copy
# .env.example to .env and run" recipe fails with a missing-key error.
ENV_FILE = Path(__file__).resolve().parent.parent / ".env"


def _load_env_file(path: Path) -> None:
    """Export KEY=VALUE lines from `path` into the process environment.

    Mirrors systemd's EnvironmentFile semantics closely enough to matter:
    blank lines and `#` comments are skipped, an optional `export ` prefix
    and matching surrounding quotes are stripped, and a variable that is
    already set in the environment is never overridden, so a real deployment
    or an explicit shell export always wins over the file.
    """
    if not path.is_file():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        if line.startswith("export "):
            line = line[len("export "):]
        key, _, value = line.partition("=")
        key, value = key.strip(), value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        if key:
            os.environ.setdefault(key, value)


def _env_str(name: str, default: str | None = None) -> str | None:
    value = os.environ.get(name)
    return value if value not in (None, "") else default


def _env_int(name: str, default: int) -> int:
    raw = os.environ.get(name)
    return int(raw) if raw else default


def _env_float(name: str, default: float) -> float:
    raw = os.environ.get(name)
    return float(raw) if raw else default


@dataclass(frozen=True)
class Config:
    host: str
    port: int
    confidence_threshold: float
    data_dir: Path
    gemini_api_key: str | None
    gemini_model: str
    button_gpio: int
    button_led_gpio: int

    @classmethod
    def from_env(cls) -> "Config":
        _load_env_file(ENV_FILE)
        return cls(
            host=_env_str("CELLAR_HOST", "0.0.0.0"),
            port=_env_int("CELLAR_PORT", 8000),
            confidence_threshold=_env_float("CELLAR_CONFIDENCE_THRESHOLD", 0.85),
            data_dir=Path(_env_str("CELLAR_DATA_DIR", "./cellar-data")).expanduser(),
            # No default. A missing key must fail loudly (require_gemini_key),
            # never silently fall back to something that looks like a key.
            gemini_api_key=_env_str("GEMINI_API_KEY"),
            gemini_model=_env_str("CELLAR_GEMINI_MODEL", "gemini-flash-latest"),
            button_gpio=_env_int("CELLAR_BUTTON_GPIO", 17),
            button_led_gpio=_env_int("CELLAR_BUTTON_LED_GPIO", 27),
        )

    def require_gemini_key(self) -> str:
        """Fail loudly at startup if GEMINI_API_KEY is missing or blank.

        Called once, at real-service startup (main.py), so a misconfigured
        Pi never comes up half-working and fails mysteriously on the first
        photo instead.
        """
        if not self.gemini_api_key:
            raise RuntimeError(
                "GEMINI_API_KEY is not set. The real Cellar Pi service refuses "
                "to start without it. Copy pi/.env.example to pi/.env, fill in "
                "the key (source it from ~/.secrets/api-keys.env on the Mac), "
                "and re-run."
            )
        return self.gemini_api_key
