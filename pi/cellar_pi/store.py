"""Durable state for the Pi: the outbound scan queue and the cellar candidate
list. JSON on disk, atomic writes (temp-file-and-rename) so a crash or power
loss mid-write never corrupts the file (PRD §9: "the Pi holds no durable
state except its outbound queue and a cached candidate list").

Queue entries survive restart. `capturedAt` is set at capture time and never
touched again — it must preserve when the bottle was actually scanned, not
when it was later uploaded/drained (PRD §5 "degrade, don't fail").
"""
from __future__ import annotations

import base64
import json
import os
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


class Store:
    def __init__(self, data_dir: Path) -> None:
        self.data_dir = Path(data_dir)
        self.captures_dir = self.data_dir / "captures"
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.captures_dir.mkdir(parents=True, exist_ok=True)

        self._queue_path = self.data_dir / "queue.json"
        self._candidates_path = self.data_dir / "candidates.json"
        self._lock = threading.Lock()

        self._queue: list[dict[str, Any]] = self._load_json(self._queue_path, [])
        self._candidates: list[str] = self._load_json(self._candidates_path, [])

    # ---- generic JSON persistence -----------------------------------

    @staticmethod
    def _load_json(path: Path, default: Any) -> Any:
        if not path.exists():
            return default
        try:
            return json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            # Corrupt or unreadable file: degrade to empty rather than crash
            # the service at startup.
            return default

    @staticmethod
    def _atomic_write_json(path: Path, data: Any) -> None:
        tmp = path.with_name(f".{path.name}.tmp-{os.getpid()}-{uuid.uuid4().hex}")
        tmp.write_text(json.dumps(data, indent=2))
        os.replace(tmp, path)  # atomic within the same filesystem

    # ---- outbound queue ------------------------------------------------

    def enqueue(
        self,
        photo_bytes: bytes,
        candidates: list[dict[str, Any]],
        confidence: float,
        captured_at: datetime | None = None,
        voice_note: str | None = None,
    ) -> dict[str, Any]:
        entry_id = uuid.uuid4().hex
        captured_at = captured_at or datetime.now(timezone.utc)

        photo_path = self.captures_dir / f"{entry_id}.jpg"
        photo_path.write_bytes(photo_bytes)

        entry = {
            "id": entry_id,
            "photoPath": str(photo_path),
            "candidates": candidates,
            "confidence": confidence,
            "capturedAt": captured_at.isoformat(),
            "voiceNote": voice_note,
        }
        with self._lock:
            self._queue.append(entry)
            self._atomic_write_json(self._queue_path, self._queue)
        return entry

    def list_queue_for_api(self) -> list[dict[str, Any]]:
        """Entries as the /queue contract wants them: photoBase64, not a path."""
        with self._lock:
            entries = list(self._queue)
        out = []
        for entry in entries:
            photo_b64 = ""
            photo_path = Path(entry["photoPath"])
            if photo_path.exists():
                photo_b64 = base64.b64encode(photo_path.read_bytes()).decode("ascii")
            out.append(
                {
                    "id": entry["id"],
                    "photoBase64": photo_b64,
                    "candidates": entry["candidates"],
                    "confidence": entry["confidence"],
                    "capturedAt": entry["capturedAt"],
                    "voiceNote": entry.get("voiceNote"),
                }
            )
        return out

    def queue_len(self) -> int:
        with self._lock:
            return len(self._queue)

    def dequeue(self, entry_id: str) -> bool:
        with self._lock:
            match = next((e for e in self._queue if e["id"] == entry_id), None)
            if match is None:
                return False
            self._queue = [e for e in self._queue if e["id"] != entry_id]
            self._atomic_write_json(self._queue_path, self._queue)

        photo_path = Path(match["photoPath"])
        try:
            photo_path.unlink(missing_ok=True)
        except OSError:
            pass  # never let cleanup failure block the ack
        return True

    # ---- candidate list (PUT /candidates) -------------------------------

    def set_candidates(self, wines: list[str]) -> None:
        with self._lock:
            self._candidates = list(wines)
            self._atomic_write_json(self._candidates_path, self._candidates)

    def get_candidates(self) -> list[str]:
        with self._lock:
            return list(self._candidates)
