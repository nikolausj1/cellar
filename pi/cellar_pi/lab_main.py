"""Lab Cellar Pi entrypoint: REAL Gemini recognizer + MOCK hardware.

Runs on macOS TODAY, with no Pi hardware, so real wine-label recognition can
be exercised straight from the iPhone app before any camera/button/LCD
exists. `POST /recognize` reads the photo from the client's HTTP upload, not
from hardware (see `api.py`), so pairing a real recognizer with mock
hardware is not a compromise — it is exactly the pairing this lab mode
needs: real Gemini calls, no Pi required.

Wires GeminiRecognizer + MockHardware into the exact same route handlers the
real service uses (`cellar_pi.api.create_app`), so the API contract cannot
drift between lab and real. Unlike mock_main.py, this does NOT add
POST /mock/press — hardware capture isn't the point here, real recognition
is.

SECURITY / SCOPE WARNING: unlike mock_main.py (which hardcodes loopback),
this binds `config.host`, which defaults to LAN-reachable `0.0.0.0`. That is
deliberate — the whole point of lab mode is that an iPhone on the same WiFi
can reach it without a Pi in between. But that means:
  - There is NO authentication on this server.
  - Anyone on the same network can call POST /recognize and spend YOUR
    Gemini quota (and, if the model changes, potentially cost money).
  - This is a lab/dev tool for testing on a trusted home network, not a
    deployment. Do not run it on a network you don't trust, and do not
    leave it running unattended for long stretches.

Fails loudly at import/startup if GEMINI_API_KEY is missing (config.py) —
never at the first /recognize request, exactly like main.py.

Run: `python -m cellar_pi.lab_main` (see pi/README.md "Lab mode" section
for the full venv + install + phone walkthrough).
"""
from __future__ import annotations

import logging
import socket

import uvicorn
from fastapi import FastAPI

from cellar_pi.api import create_app
from cellar_pi.config import Config
from cellar_pi.hardware import ConsoleDisplay, MockHardware
from cellar_pi.recognizer import GeminiRecognizer
from cellar_pi.store import Store

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("cellar_pi.lab_main")


def build() -> tuple[FastAPI, Config]:
    config = Config.from_env()
    config.require_gemini_key()  # fail loudly now, not on first /recognize

    store = Store(config.data_dir)
    recognizer = GeminiRecognizer(api_key=config.gemini_api_key, model=config.gemini_model)
    display = ConsoleDisplay()
    hardware = MockHardware(display)

    app = create_app(recognizer, hardware, store)

    hardware.register_press_handler(lambda hold: None)  # no real GPIO to wire
    display.show("idle (lab)", "idle")
    return app, config


def _local_ips() -> list[str]:
    """Best-effort local LAN IP detection so the owner can type a URL into
    his phone without hunting for it himself. Never raises — falls back to
    an empty list if detection fails for any reason (e.g. no network)."""
    ips: set[str] = set()
    try:
        # Doesn't actually send anything (UDP, no connect handshake) — just
        # asks the OS which local interface would be used to reach the
        # internet, which is a reliable way to find the LAN-facing IP.
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("8.8.8.8", 80))
            ips.add(s.getsockname()[0])
    except OSError:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if not ip.startswith("127."):
                ips.add(ip)
    except OSError:
        pass
    return sorted(ips)


def main() -> None:
    app, config = build()
    logger.info(
        "Cellar Pi LAB starting on http://%s:%s — REAL Gemini recognizer, MOCK "
        "hardware. No authentication: anyone on this network can call "
        "/recognize and spend Gemini quota. Lab/dev tool only.",
        config.host,
        config.port,
    )
    for ip in _local_ips():
        logger.info("Point the iPhone app at: http://%s:%s", ip, config.port)
    uvicorn.run(app, host=config.host, port=config.port)


if __name__ == "__main__":
    main()
