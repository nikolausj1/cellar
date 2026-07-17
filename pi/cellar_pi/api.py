"""The API contract. Routes live here ONCE — `create_app()` is called by
both main.py (real: Gemini + Pi hardware) and mock_main.py (fake recognizer,
no hardware) with different implementations of the same protocols, so the
two entrypoints can never drift apart on the wire format.

`capture_and_enqueue()` is exported but is NOT a route: it's the shared
button-press pipeline (capture -> recognize -> queue -> update the display)
used by main.py's real GPIO callback and mock_main.py's POST /mock/press.
It lives here because it is exactly as shared as the routes are, just not
reachable directly over HTTP on the real service.
"""
from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

from fastapi import FastAPI, File, Form, HTTPException, Query, UploadFile
from pydantic import BaseModel

from cellar_pi.hardware import Hardware
from cellar_pi.recognizer import Recognizer, RecognizerError
from cellar_pi.store import Store

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Wire models (exact API contract)
# ---------------------------------------------------------------------------


class Candidate(BaseModel):
    producer: str
    name: str
    vintage: int | None = None
    region: str | None = None
    varietal: str | None = None
    bottleSize: str


class RecognizeResponse(BaseModel):
    candidates: list[Candidate]
    confidence: float


class EnrichRequest(BaseModel):
    producer: str
    name: str
    vintage: int | None = None
    region: str | None = None
    varietal: str | None = None


class EnrichResponse(BaseModel):
    drinkWindowStart: int | None
    drinkWindowEnd: int | None
    tastingNotes: str
    pairings: list[str]
    estimatedValue: float | None


class QueueEntry(BaseModel):
    id: str
    photoBase64: str
    candidates: list[Candidate]
    confidence: float
    capturedAt: str
    voiceNote: str | None = None


class QueueResponse(BaseModel):
    entries: list[QueueEntry]


class CandidatesPut(BaseModel):
    wines: list[str]


class HealthResponse(BaseModel):
    ok: bool
    hardware: str
    recognizer: str
    queued: int


class OkResponse(BaseModel):
    ok: bool


# ---------------------------------------------------------------------------
# App factory
# ---------------------------------------------------------------------------


def _recognizer_error_detail(exc: RecognizerError) -> str:
    """Turn a RecognizerError into an actionable 502 detail. When Gemini
    itself answered, the detail is derived from the status alone — never the
    raw upstream body. Without an upstream status the message is one
    recognizer.py authored itself (mock's scenario=fail, "Gemini request
    failed: timeout", ...) — key-safe by construction there, and worth
    passing through so a timeout is distinguishable from a rejection."""
    status = exc.upstream_status
    if status in (400, 401, 403):
        return f"Recognizer upstream rejected the request (HTTP {status}) — check GEMINI_API_KEY"
    if status == 429:
        return "Recognizer upstream is rate-limited (HTTP 429) — try again shortly"
    if status is not None:
        return f"Recognizer upstream failed (HTTP {status})"
    return str(exc)


def create_app(recognizer: Recognizer, hardware: Hardware, store: Store) -> FastAPI:
    app = FastAPI(title="Cellar Pi", version="0.1.0")

    @app.get("/health", response_model=HealthResponse)
    async def health() -> dict[str, Any]:
        return {
            "ok": True,
            "hardware": hardware.kind,
            "recognizer": recognizer.name,
            "queued": store.queue_len(),
        }

    @app.post("/recognize", response_model=RecognizeResponse)
    async def recognize(
        image: UploadFile = File(...),
        hint: str | None = Form(None),
        scenario_form: str | None = Form(None, alias="scenario"),
        scenario_query: str | None = Query(None, alias="scenario"),
    ) -> dict[str, Any]:
        scenario = scenario_form or scenario_query
        image_bytes = await image.read()
        cellar_wines = store.get_candidates()
        try:
            result = await recognizer.recognize(
                image_bytes, hint=hint, cellar_wines=cellar_wines, scenario=scenario
            )
        except RecognizerError as exc:
            # Honest failure, not a floor on confidence. The phone treats
            # this like any other network failure and queues the photo
            # itself (PRD §6.2) — the Pi never pretends to have an answer.
            # 502 (bad gateway), not 500: the Pi itself is fine, it's the
            # upstream recognizer that rejected/failed the call.
            logger.warning("recognize: recognizer failed: %s", exc)
            raise HTTPException(status_code=502, detail=_recognizer_error_detail(exc)) from exc
        return result

    @app.post("/enrich", response_model=EnrichResponse)
    async def enrich(payload: EnrichRequest) -> dict[str, Any]:
        try:
            result = await recognizer.enrich(payload.model_dump())
        except RecognizerError as exc:
            logger.warning("enrich: recognizer failed: %s", exc)
            raise HTTPException(status_code=502, detail=_recognizer_error_detail(exc)) from exc
        return result

    @app.get("/queue", response_model=QueueResponse)
    async def get_queue() -> dict[str, Any]:
        return {"entries": store.list_queue_for_api()}

    @app.delete("/queue/{entry_id}", response_model=OkResponse)
    async def delete_queue_entry(entry_id: str) -> dict[str, Any]:
        removed = store.dequeue(entry_id)
        if not removed:
            raise HTTPException(status_code=404, detail="queue entry not found")
        return {"ok": True}

    @app.put("/candidates", response_model=OkResponse)
    async def put_candidates(payload: CandidatesPut) -> dict[str, Any]:
        store.set_candidates(payload.wines)
        return {"ok": True}

    return app


# ---------------------------------------------------------------------------
# Shared button-press pipeline (not a route)
# ---------------------------------------------------------------------------


def _wine_label(candidate: dict[str, Any]) -> str:
    vintage = candidate.get("vintage")
    producer = candidate.get("producer", "")
    name = candidate.get("name", "")
    label = f"{producer} {name}".strip()
    return f"{label} {vintage}".strip() if vintage else label


async def capture_and_enqueue(
    hardware: Hardware,
    recognizer: Recognizer,
    store: Store,
    confidence_threshold: float,
    hold: bool = False,
) -> dict[str, Any]:
    """Capture -> recognize -> queue -> update the display. Used by both the
    real button (main.py, via PiHardware's press handler) and the mock
    button (mock_main.py's POST /mock/press).

    Principle "capture, never decide" (PRD §5): this NEVER raises for a
    recognition failure — it always enqueues something and always updates
    the display, even when Gemini is unreachable. `capturedAt` is stamped
    the moment the photo is taken, before any network call, so it survives
    an offline period untouched (PRD §6.5 "timestamps preserve when he
    actually drank it").
    """
    captured_at = datetime.now(timezone.utc)
    hardware.display.show("Capturing…", "capturing")
    hardware.set_button_led(False)

    photo_bytes = hardware.capture_photo()

    voice_note: str | None = None
    if hold:
        # Press-and-hold: record a voice note. Stubbed behind
        # VoiceRecorder — see hardware.NullVoiceRecorder's TODO.
        voice_note = hardware.voice_recorder.record_and_transcribe()

    cellar_wines = store.get_candidates()
    try:
        result = await recognizer.recognize(photo_bytes, cellar_wines=cellar_wines)
        candidates = list(result.get("candidates", []))
        confidence = float(result.get("confidence", 0.0))
    except RecognizerError as exc:
        # Degrade, don't fail (PRD §5): still capture, still queue, show
        # offline. Never block, never drop the bottle.
        logger.warning("capture_and_enqueue: recognition failed, queuing offline: %s", exc)
        candidates, confidence = [], 0.0
        entry = store.enqueue(photo_bytes, candidates, confidence, captured_at, voice_note)
        hardware.display.show("⚠ offline, queued", "offline")
        hardware.set_button_led(True)
        return entry

    entry = store.enqueue(photo_bytes, candidates, confidence, captured_at, voice_note)

    if candidates and confidence >= confidence_threshold:
        hardware.display.show(f"✓ {_wine_label(candidates[0])}", "confirmed")
    else:
        # Low confidence still logs (never rejects) — it only changes the
        # display, per CELLAR_CONFIDENCE_THRESHOLD's documented scope.
        hardware.display.show("? Logged, needs review", "review")

    hardware.set_button_led(True)
    return entry
