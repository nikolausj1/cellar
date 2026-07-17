"""Real Cellar Pi entrypoint: Gemini recognizer + Pi hardware (camera,
button, LED, LCD console stand-in).

Deploy-later: this only runs on the Pi (requirements.txt, picamera2 +
gpiozero). Do not attempt to run this on macOS — use mock_main.py there.

Fails loudly at import/startup if GEMINI_API_KEY is missing (config.py) —
never at the first request.
"""
from __future__ import annotations

import asyncio
import logging

import uvicorn
from fastapi import FastAPI

from cellar_pi.api import capture_and_enqueue, create_app
from cellar_pi.config import Config
from cellar_pi.hardware import ConsoleDisplay, PiHardware
from cellar_pi.recognizer import GeminiRecognizer
from cellar_pi.store import Store

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("cellar_pi.main")


def build() -> tuple[FastAPI, Config]:
    config = Config.from_env()
    config.require_gemini_key()  # fail loudly now, not on first /recognize

    store = Store(config.data_dir)
    recognizer = GeminiRecognizer(api_key=config.gemini_api_key, model=config.gemini_model)
    # TODO(display): swap ConsoleDisplay for a real LCD driver once the
    # model is chosen (PRD §12 open question 4). Everything else is
    # written against the Display protocol and needs no changes.
    display = ConsoleDisplay()
    hardware = PiHardware(config, display)

    app = create_app(recognizer, hardware, store)

    @app.on_event("startup")
    async def _wire_button() -> None:
        loop = asyncio.get_running_loop()

        def on_press(hold: bool) -> None:
            asyncio.run_coroutine_threadsafe(
                capture_and_enqueue(
                    hardware, recognizer, store, config.confidence_threshold, hold=hold
                ),
                loop,
            )

        hardware.register_press_handler(on_press)
        hardware.set_button_led(True)
        display.show("idle", "idle")
        logger.info("Cellar Pi ready: button armed, camera warm.")

    return app, config


def main() -> None:
    app, config = build()
    uvicorn.run(app, host=config.host, port=config.port)


if __name__ == "__main__":
    main()
