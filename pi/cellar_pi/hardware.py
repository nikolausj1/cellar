"""Hardware abstraction: camera, button, LED, and display.

`Hardware` is the protocol api.py's factory is written against. `PiHardware`
is the real Pi 4/5 + Camera Module 3 + gpiozero implementation (written now,
run later — the hardware does not exist yet). `MockHardware` runs on macOS
today with zero Pi dependencies.

`Display` is intentionally a thin protocol: the LCD model is undecided (PRD
§12 open question 4), so this file does NOT pick a driver library. Only a
protocol and a console implementation exist. Swap in a real driver
(ST7789/ST7735/HD44780/whatever arrives) behind `Display` once the part is
in hand — nothing else in the codebase should need to change.
"""
from __future__ import annotations

import base64
import io
import time
from typing import Callable, Protocol

# ---------------------------------------------------------------------------
# Display
# ---------------------------------------------------------------------------


class Display(Protocol):
    """PRD §6.5 display states: idle / capturing / "✓ <wine>" /
    "? Logged, needs review" / "⚠ offline, queued". `kind` is a free-form
    tag (e.g. "idle", "capturing", "confirmed", "review", "offline", "error")
    a real driver can use to pick an icon/color; the console impl ignores it.
    """

    def show(self, text: str, kind: str = "info") -> None: ...


class ConsoleDisplay:
    """Stand-in for the undecided LCD (PRD §12 Q4). Good enough to develop
    and test the whole capture pipeline before any part is ordered."""

    def show(self, text: str, kind: str = "info") -> None:
        print(f"[LCD:{kind}] {text}")


# ---------------------------------------------------------------------------
# Voice notes (press-and-hold) — stub only, per spec
# ---------------------------------------------------------------------------


class VoiceRecorder(Protocol):
    def record_and_transcribe(self) -> str | None: ...


class NullVoiceRecorder:
    """TODO(voice-notes): press-and-hold (>1.5s) is wired end-to-end in
    PiHardware (see _on_released below) and correctly reaches this point,
    but recording + transcription is intentionally NOT implemented per the
    build spec. Implement once the mic hardware is chosen: record audio for
    the hold duration, transcribe (e.g. local whisper.cpp or a cloud API),
    return the transcript. Return None on any failure — a missing voice
    note must never block the capture (PRD §5 degrade, don't fail); the
    memory cascade's next rung (app-open prompt, PRD §6.6) covers it.
    """

    def record_and_transcribe(self) -> str | None:
        return None


# ---------------------------------------------------------------------------
# Hardware protocol
# ---------------------------------------------------------------------------

PressHandler = Callable[[bool], None]  # handler(is_hold: bool)


class Hardware(Protocol):
    kind: str  # "pi" | "mock" — surfaced on GET /health
    display: Display
    voice_recorder: VoiceRecorder

    def capture_photo(self) -> bytes: ...

    def set_button_led(self, on: bool) -> None: ...

    def register_press_handler(self, handler: PressHandler) -> None:
        """Register the callback fired on a completed button press.
        Implementations call handler(is_hold) from whatever thread detects
        the press; callers (main.py) are responsible for hopping back onto
        the asyncio loop if they need to await anything."""
        ...


# ---------------------------------------------------------------------------
# Real Pi hardware
# ---------------------------------------------------------------------------


class PiHardware:
    """Camera Module 3 (autofocus) + gpiozero button/LED.

    NOTE: Camera Module 3 autofocus is required. At the ~15cm distance a
    bottle held up to the scan station sits from the lens, a fixed-focus
    camera (e.g. Camera Module 3 NOFIR variants without AF, or an older
    Module 2) returns an unreadable blur. Do not substitute a fixed-focus
    module (PRD §9).
    """

    kind = "pi"

    def __init__(self, config, display: Display) -> None:
        try:
            from picamera2 import Picamera2  # type: ignore[import-not-found]
        except ImportError as exc:  # pragma: no cover - only exercised on the Pi
            raise RuntimeError(
                "picamera2 is required for PiHardware. Install it via apt "
                "(python3-picamera2) as documented in setup.sh — it is not "
                "pip-installable on most systems."
            ) from exc
        try:
            from gpiozero import Button, LED  # type: ignore[import-not-found]
        except ImportError as exc:  # pragma: no cover - only exercised on the Pi
            raise RuntimeError(
                "gpiozero is required for PiHardware. See requirements.txt."
            ) from exc

        self.display = display
        self.voice_recorder = NullVoiceRecorder()

        self._picam2 = Picamera2()
        still_config = self._picam2.create_still_configuration()
        self._picam2.configure(still_config)
        # AfMode 2 = continuous autofocus (libcamera enum). Required — see
        # class docstring. Do not change to a fixed AfMode.
        self._picam2.set_controls({"AfMode": 2})
        self._picam2.start()
        # Let AF settle before the first real capture.
        time.sleep(1.0)

        self._led = LED(config.button_led_gpio)
        self._button = Button(config.button_gpio, bounce_time=0.05)
        self._button.when_pressed = self._on_pressed
        self._button.when_released = self._on_released

        self._press_started_at: float | None = None
        self._handler: PressHandler | None = None

        self.HOLD_THRESHOLD_SECONDS = 1.5

    def register_press_handler(self, handler: PressHandler) -> None:
        self._handler = handler

    def _on_pressed(self) -> None:
        self._press_started_at = time.monotonic()

    def _on_released(self) -> None:
        if self._press_started_at is None or self._handler is None:
            return
        held = (time.monotonic() - self._press_started_at) >= self.HOLD_THRESHOLD_SECONDS
        self._press_started_at = None
        self._handler(held)

    def capture_photo(self) -> bytes:
        buf = io.BytesIO()
        self._picam2.capture_file(buf, format="jpeg")
        return buf.getvalue()

    def set_button_led(self, on: bool) -> None:
        if on:
            self._led.on()
        else:
            self._led.off()


# ---------------------------------------------------------------------------
# Mock hardware — no GPIO, no camera
# ---------------------------------------------------------------------------

# A tiny (2x2) valid JPEG, embedded so the mock never touches a real camera
# or the filesystem for its fixture. Content is irrelevant: MockRecognizer
# ignores image bytes and rotates canned wines regardless of what's "seen".
_PLACEHOLDER_JPEG_B64 = (
    "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0a"
    "HBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAACAAIBAREA/8QAFQABAQAAAAAA"
    "AAAAAAAAAAAAAAj/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/"
    "xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCdABmX/9k="
)


class MockHardware:
    """No GPIO, no camera — runs on macOS. `simulate_press()` is called by
    the mock entrypoint's POST /mock/press route (NOT part of the shared
    route factory) to exercise the same capture pipeline the real button
    would trigger."""

    kind = "mock"

    def __init__(self, display: Display) -> None:
        self.display = display
        self.voice_recorder = NullVoiceRecorder()
        self._handler: PressHandler | None = None
        self._led_on = False
        self._fixture_jpeg = base64.b64decode(_PLACEHOLDER_JPEG_B64)

    def register_press_handler(self, handler: PressHandler) -> None:
        self._handler = handler

    def simulate_press(self, hold: bool = False) -> None:
        if self._handler is not None:
            self._handler(hold)

    def capture_photo(self) -> bytes:
        return self._fixture_jpeg

    def set_button_led(self, on: bool) -> None:
        self._led_on = on
