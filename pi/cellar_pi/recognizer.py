"""Recognizer protocol + implementations.

`recognize()` powers POST /recognize (label photo -> ranked wine candidates).
`enrich()` powers POST /enrich (drink window / tasting notes / pairings /
estimated value — PRD §6.9, one Gemini call per unique wine, cached forever
by the phone; deliberately separate from recognize, do not merge).

Both are async so the shared FastAPI routes in api.py never block the event
loop on a slow model call.
"""
from __future__ import annotations

import asyncio
import base64
import itertools
import json
import logging
import random
import threading
from typing import TYPE_CHECKING, Any, Protocol

if TYPE_CHECKING:
    import httpx

logger = logging.getLogger(__name__)

GEMINI_ENDPOINT = (
    "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
)


class RecognizerError(Exception):
    """Recognition/enrichment failed (network, API error, bad response
    shape). api.py turns this into a 500 so the caller can degrade
    gracefully — the phone re-queues the photo, the Pi's own capture
    pipeline still logs the bottle and shows "offline, queued" (PRD §5)."""


class Recognizer(Protocol):
    name: str  # "gemini" | "mock" — surfaced on GET /health

    async def recognize(
        self,
        image_bytes: bytes,
        hint: str | None = None,
        cellar_wines: list[str] | None = None,
        scenario: str | None = None,
    ) -> dict[str, Any]:
        """Returns {"candidates": [...up to 3, best first], "confidence": float}."""
        ...

    async def enrich(self, wine: dict[str, Any]) -> dict[str, Any]:
        """Returns {"drinkWindowStart", "drinkWindowEnd", "tastingNotes",
        "pairings", "estimatedValue"}."""
        ...


# ---------------------------------------------------------------------------
# Gemini
# ---------------------------------------------------------------------------

# Gemini's structured-output schema is a restricted OpenAPI subset:
# UPPERCASE type names, "nullable": true instead of JSON Schema unions.
_RECOGNIZE_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "candidates": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "producer": {"type": "STRING"},
                    "name": {"type": "STRING"},
                    "vintage": {"type": "INTEGER", "nullable": True},
                    "region": {"type": "STRING", "nullable": True},
                    "varietal": {"type": "STRING", "nullable": True},
                    "bottleSize": {"type": "STRING"},
                },
                "required": ["producer", "name", "bottleSize"],
            },
        },
        "confidence": {"type": "NUMBER"},
    },
    "required": ["candidates", "confidence"],
}

_ENRICH_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "drinkWindowStart": {"type": "INTEGER", "nullable": True},
        "drinkWindowEnd": {"type": "INTEGER", "nullable": True},
        "tastingNotes": {"type": "STRING"},
        "pairings": {"type": "ARRAY", "items": {"type": "STRING"}},
        "estimatedValue": {"type": "NUMBER", "nullable": True},
    },
    "required": ["tastingNotes", "pairings"],
}


def _build_recognize_prompt(hint: str | None, cellar_wines: list[str]) -> str:
    lines = [
        "You are looking at a photo of a single wine bottle label, held in a "
        "hand with the label facing the camera.",
        "Identify the wine. Return your best guess plus up to two plausible "
        "alternates, ordered best first.",
        "For each candidate give: producer, name, vintage (an integer year, "
        "or null if the vintage is not legible or the wine is non-vintage), "
        "region, varietal, and bottleSize (e.g. '750ml', 'magnum', '1.5L').",
        "Give an honest confidence for your TOP candidate only, from 0.0 to "
        "1.0. Do not inflate it to seem helpful — a low confidence on a "
        "genuinely unclear label is more useful than false certainty. Do "
        "not floor it at some 'comfortable' minimum either.",
    ]
    if cellar_wines:
        wines_str = "; ".join(cellar_wines)
        lines.append(
            "The collection this bottle likely belongs to already contains "
            f"these wines: {wines_str}. Treat this as a PREFERENCE, not a "
            "constraint — prefer matching one of them ONLY if the label "
            "genuinely matches. A forced match to a known wine is worse "
            "than an honest unknown; if the bottle isn't one of these, "
            "identify it freely."
        )
    if hint:
        lines.append(
            f"The user has provided a one-word hint to narrow the match: "
            f"'{hint}'. Use it to disambiguate, but still report your "
            "honest confidence."
        )
    return "\n".join(lines)


def _build_enrich_prompt(wine: dict[str, Any]) -> str:
    desc = ", ".join(f"{k}={v}" for k, v in wine.items() if v not in (None, ""))
    return (
        "You are a wine expert. For the following wine, provide: an "
        "estimated drink window (start and end year as integers — null for "
        "either if you cannot reasonably estimate, e.g. a wine not meant "
        "for aging), brief tasting notes (2-3 sentences), 3-5 food pairing "
        "suggestions, and an estimated current market value in USD for one "
        "bottle (a rough, directional number — null if you cannot "
        "reasonably estimate). Be honest about uncertainty; a clearly "
        "rough estimate is more useful than false precision.\n\n"
        f"Wine: {desc}"
    )


class GeminiRecognizer:
    """Only this class touches httpx, and only when instantiated — real
    Pi service only (requirements.txt). Imported lazily so recognizer.py
    itself stays importable on macOS with just requirements-mock.txt (the
    mock never constructs a GeminiRecognizer)."""

    name = "gemini"

    def __init__(
        self,
        api_key: str,
        model: str,
        client: "httpx.AsyncClient | None" = None,
        timeout_seconds: float = 30.0,
    ) -> None:
        try:
            import httpx
        except ImportError as exc:  # pragma: no cover - only hit without requirements.txt
            raise RuntimeError(
                "httpx is required for GeminiRecognizer. Install requirements.txt "
                "(the real-service deps) — the mock does not need it."
            ) from exc

        self._httpx = httpx
        self._api_key = api_key  # never logged, never included in exception text
        self._model = model
        self._client = client or httpx.AsyncClient(timeout=timeout_seconds)

    async def recognize(
        self,
        image_bytes: bytes,
        hint: str | None = None,
        cellar_wines: list[str] | None = None,
        scenario: str | None = None,
    ) -> dict[str, Any]:
        cellar_wines = cellar_wines or []
        prompt = _build_recognize_prompt(hint, cellar_wines)
        body = {
            "contents": [
                {
                    "parts": [
                        {"text": prompt},
                        {
                            "inline_data": {
                                "mime_type": "image/jpeg",
                                "data": base64.b64encode(image_bytes).decode("ascii"),
                            }
                        },
                    ]
                }
            ],
            "generationConfig": {
                "responseMimeType": "application/json",
                "responseSchema": _RECOGNIZE_SCHEMA,
            },
        }
        data = await self._call_gemini(body)
        candidates = list(data.get("candidates", []))[:3]
        confidence = float(data.get("confidence", 0.0))
        return {"candidates": candidates, "confidence": confidence}

    async def enrich(self, wine: dict[str, Any]) -> dict[str, Any]:
        prompt = _build_enrich_prompt(wine)
        body = {
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {
                "responseMimeType": "application/json",
                "responseSchema": _ENRICH_SCHEMA,
            },
        }
        data = await self._call_gemini(body)
        return {
            "drinkWindowStart": data.get("drinkWindowStart"),
            "drinkWindowEnd": data.get("drinkWindowEnd"),
            "tastingNotes": data.get("tastingNotes", ""),
            "pairings": list(data.get("pairings", [])),
            "estimatedValue": data.get("estimatedValue"),
        }

    async def _call_gemini(self, body: dict[str, Any]) -> dict[str, Any]:
        url = GEMINI_ENDPOINT.format(model=self._model)
        try:
            resp = await self._client.post(
                url,
                headers={
                    "X-goog-api-key": self._api_key,
                    "Content-Type": "application/json",
                },
                json=body,
            )
            resp.raise_for_status()
        except self._httpx.HTTPError as exc:
            # httpx error text/repr does not include our custom headers, so
            # this cannot leak the key. Do not add exc.request details.
            logger.warning("Gemini call failed: %s", exc.__class__.__name__)
            raise RecognizerError(f"Gemini request failed: {exc}") from exc

        payload = resp.json()
        try:
            text = payload["candidates"][0]["content"]["parts"][0]["text"]
        except (KeyError, IndexError, TypeError) as exc:
            raise RecognizerError("Gemini returned an unexpected response shape") from exc

        try:
            return json.loads(text)
        except json.JSONDecodeError as exc:
            raise RecognizerError("Gemini returned non-JSON despite responseSchema") from exc


# ---------------------------------------------------------------------------
# Mock — zero network, zero API key, instant
# ---------------------------------------------------------------------------

_MOCK_WINES: list[dict[str, Any]] = [
    {
        "producer": "Ornellaia",
        "name": "Ornellaia",
        "vintage": 2015,
        "region": "Bolgheri, Italy",
        "varietal": "Bordeaux Blend",
        "bottleSize": "750ml",
    },
    {
        "producer": "Caymus",
        "name": "Cabernet Sauvignon",
        "vintage": 2021,
        "region": "Napa Valley, California",
        "varietal": "Cabernet Sauvignon",
        "bottleSize": "750ml",
    },
    {
        "producer": "Duckhorn",
        "name": "Merlot",
        "vintage": 2019,
        "region": "Napa Valley, California",
        "varietal": "Merlot",
        "bottleSize": "750ml",
    },
    {
        "producer": "Silver Oak",
        "name": "Cabernet Sauvignon",
        "vintage": 2019,
        "region": "Alexander Valley, California",
        "varietal": "Cabernet Sauvignon",
        "bottleSize": "750ml",
    },
    {
        "producer": "Ridge",
        "name": "Zinfandel",
        "vintage": 2020,
        "region": "Sonoma County, California",
        "varietal": "Zinfandel",
        "bottleSize": "750ml",
    },
    {
        "producer": "Beringer",
        "name": "Knights Valley Cabernet Sauvignon",
        "vintage": 2018,
        "region": "Knights Valley, California",
        "varietal": "Cabernet Sauvignon",
        "bottleSize": "750ml",
    },
]


class MockRecognizer:
    """Zero network, zero API key, instant. Rotates through plausible wines
    so the iOS map/queue shows variety during development.

    Scenario forcing via `scenario` (form field or query param on
    POST /recognize): "high" (~0.97), "low" (~0.42, forces the iOS review
    queue), "fail" (raises -> api.py returns 500), "slow" (~5s sleep, to
    prove the iOS add flow never blocks on recognition). Default: mostly
    high, every 5th request low, so the review queue gets exercised
    naturally without anyone having to force it.
    """

    name = "mock"

    def __init__(self) -> None:
        self._counter = itertools.count(1)
        self._lock = threading.Lock()

    def _next_index(self) -> int:
        with self._lock:
            return next(self._counter)

    async def recognize(
        self,
        image_bytes: bytes,
        hint: str | None = None,
        cellar_wines: list[str] | None = None,
        scenario: str | None = None,
    ) -> dict[str, Any]:
        n = self._next_index()

        if scenario == "fail":
            raise RecognizerError("mock scenario=fail: simulated recognition failure")
        if scenario == "slow":
            await asyncio.sleep(5)

        count = len(_MOCK_WINES)
        base = n % count
        top = dict(_MOCK_WINES[base])
        alt1 = dict(_MOCK_WINES[(base + 1) % count])
        alt2 = dict(_MOCK_WINES[(base + 2) % count])

        if hint:
            hint_lower = hint.lower()
            matched = next(
                (
                    w
                    for w in _MOCK_WINES
                    if w["producer"].lower().startswith(hint_lower)
                    or w["name"].lower().startswith(hint_lower)
                ),
                None,
            )
            if matched:
                top = dict(matched)

        if scenario == "high":
            confidence = round(random.uniform(0.95, 0.99), 2)
        elif scenario == "low":
            confidence = round(random.uniform(0.38, 0.46), 2)
        elif n % 5 == 0:
            confidence = round(random.uniform(0.38, 0.46), 2)
        else:
            confidence = round(random.uniform(0.90, 0.99), 2)

        return {"candidates": [top, alt1, alt2], "confidence": confidence}

    async def enrich(self, wine: dict[str, Any]) -> dict[str, Any]:
        vintage = wine.get("vintage") or 2018
        producer = wine.get("producer", "Unknown")
        name = wine.get("name", "")
        return {
            "drinkWindowStart": int(vintage) + 2,
            "drinkWindowEnd": int(vintage) + 12,
            "tastingNotes": (
                f"Mock tasting notes for {producer} {name}: dark fruit, firm "
                "tannins, long finish. (This is fixture data — MockRecognizer "
                "never calls a model.)"
            ),
            "pairings": ["Grilled steak", "Aged cheddar", "Roasted lamb"],
            "estimatedValue": 85.0,
        }
