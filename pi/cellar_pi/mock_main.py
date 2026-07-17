"""Mock Cellar Pi entrypoint — runs on macOS TODAY with zero Pi dependencies.

Wires MockRecognizer + MockHardware into the exact same route handlers the
real service uses (`cellar_pi.api.create_app`), so the API contract cannot
drift between mock and real. The only addition is one dev-only route,
POST /mock/press, which is NOT part of the shared factory — it simulates a
Pi button press so the /queue drain path can be exercised from curl before
any Pi hardware exists.

Run: `python -m cellar_pi.mock_main` (see pi/README.md for the full
venv + install + curl walkthrough).
"""
from __future__ import annotations

import logging

import uvicorn
from fastapi import FastAPI, Query

from cellar_pi.api import capture_and_enqueue, create_app
from cellar_pi.config import Config
from cellar_pi.hardware import ConsoleDisplay, MockHardware
from cellar_pi.recognizer import MockRecognizer
from cellar_pi.store import Store

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("cellar_pi.mock_main")

# Mock always binds loopback-only, regardless of CELLAR_HOST in .env (which
# defaults to 0.0.0.0 for the Pi's benefit). Running on a laptop should
# never open a LAN-reachable port by accident.
MOCK_BIND_HOST = "127.0.0.1"


def build_mock_app() -> tuple[FastAPI, Config]:
    config = Config.from_env()  # GEMINI_API_KEY is NOT required for the mock

    store = Store(config.data_dir)
    recognizer = MockRecognizer()
    display = ConsoleDisplay()
    hardware = MockHardware(display)

    app = create_app(recognizer, hardware, store)

    @app.post("/mock/press", tags=["mock-only"])
    async def mock_press(
        hold: bool = Query(
            False,
            description="Simulate press-and-hold (>1.5s): captures AND records a voice note.",
        ),
    ) -> dict:
        """Mock/dev only — not part of the shared API contract. Simulates a
        Pi button press end-to-end (capture -> recognize -> queue -> LCD),
        so `GET /queue` and `DELETE /queue/{id}` can be exercised from curl
        before any Pi hardware exists."""
        entry = await capture_and_enqueue(
            hardware, recognizer, store, config.confidence_threshold, hold=hold
        )
        return {"ok": True, "queued": entry["id"]}

    hardware.register_press_handler(lambda hold: None)  # no real GPIO to wire
    display.show("idle (mock)", "idle")
    return app, config


def main() -> None:
    app, config = build_mock_app()
    logger.info(
        "Cellar Pi MOCK starting on http://%s:%s — zero Pi deps, zero network calls.",
        MOCK_BIND_HOST,
        config.port,
    )
    uvicorn.run(app, host=MOCK_BIND_HOST, port=config.port)


if __name__ == "__main__":
    main()
