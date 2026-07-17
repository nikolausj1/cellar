#!/usr/bin/env python3
"""Measure the PRD's riskiest claim -- "≥90% of bottles recognized correctly
with no hint" -- against a real Pi service (mock, lab, or the real Pi) BEFORE
any hardware is ordered.

Deliberately stdlib-only (argparse/csv/json/urllib/...): the owner needs to
run this from bare `python3` on his Mac to point at a running service, not
inside the service's own venv, and not after `pip install`ing anything. It
hand-rolls the multipart POST for the same reason -- pulling in `requests`
would be the one dependency this script needed and the one thing standing
between "photograph 120 bottles" and "run this file".

Two modes, run in sequence:

  1. `accuracy_run.py PHOTOS_DIR [--url ...] [--hint ...]`
     POSTs every photo in PHOTOS_DIR to POST /recognize (see
     cellar_pi/api.py -- multipart field "image", optional form field
     "hint"), writing one CSV row per photo AS IT GOES (a crash on photo 90
     of 120 still leaves 89 rows on disk). The CSV's `verdict` column is
     left empty -- correctness is a human judgment only the owner can make
     (only he knows what's actually in each photo), this script cannot
     fake it.

  2. `accuracy_run.py --score RESULTS_CSV` (after the owner has hand-filled
     `verdict` with y/n per row)
     Reports N/M correct, split by confidence bucket, so the owner can see
     whether the model's stated confidence is actually calibrated (e.g. "is
     0.95+ actually right ~95% of the time, or does it just always say
     0.97?").
"""
from __future__ import annotations

import argparse
import csv
import json
import statistics
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib import error, request

# Extensions the server can actually use. GeminiRecognizer (recognizer.py)
# hardcodes `mime_type: "image/jpeg"` on every call regardless of what bytes
# it's handed, so a HEIC upload wouldn't fail loudly -- it would silently
# feed Gemini bytes mislabeled as JPEG and produce garbage or a Gemini-side
# decode error that's hard to distinguish from a genuine recognition miss.
# api.py itself places no content-type restriction on the upload (it just
# reads whatever bytes UploadFile hands it), so this is a client-side
# safeguard, not something the server enforces.
_CONTENT_TYPES = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png"}
_SKIP_EXTENSIONS = {".heic"}

CSV_FIELDS = [
    "filename",
    "producer",
    "name",
    "vintage",
    "confidence",
    "latency_seconds",
    "http_status",
    "error",
    "verdict",
]

# Coarse confidence buckets shared by the run summary's histogram and the
# --score mode's calibration breakdown, so the two are directly comparable.
_BUCKETS: list[tuple[float, float, str]] = [
    (0.0, 0.50, "<0.50"),
    (0.50, 0.70, "0.50-0.70"),
    (0.70, 0.85, "0.70-0.85"),
    (0.85, 0.95, "0.85-0.95"),
    (0.95, 1.01, "0.95-1.00"),  # 1.01 so a confidence of exactly 1.0 lands here
]


def _bucket_label(confidence: float) -> str:
    for low, high, label in _BUCKETS:
        if low <= confidence < high:
            return label
    return "unknown"


# ---------------------------------------------------------------------------
# Multipart POST, hand-rolled (stdlib urllib has no multipart encoder)
# ---------------------------------------------------------------------------


def _encode_multipart(image_path: Path, content_type: str, hint: str | None) -> tuple[bytes, str]:
    """Builds the exact request POST /recognize expects: multipart field
    "image" (file) plus an optional "hint" form field (api.py :: recognize).
    """
    boundary = uuid.uuid4().hex
    parts: list[bytes] = []
    parts.append(f"--{boundary}\r\n".encode())
    parts.append(
        f'Content-Disposition: form-data; name="image"; filename="{image_path.name}"\r\n'.encode()
    )
    parts.append(f"Content-Type: {content_type}\r\n\r\n".encode())
    parts.append(image_path.read_bytes())
    parts.append(b"\r\n")
    if hint:
        parts.append(f"--{boundary}\r\n".encode())
        parts.append(b'Content-Disposition: form-data; name="hint"\r\n\r\n')
        parts.append(hint.encode())
        parts.append(b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def _post_recognize(
    base_url: str, image_path: Path, content_type: str, hint: str | None, timeout: float
) -> dict[str, Any]:
    """POSTs one photo. Never raises -- a failed request is data (it belongs
    in the CSV as a failed row), not a reason to abort the whole run."""
    body, content_type_header = _encode_multipart(image_path, content_type, hint)
    url = f"{base_url.rstrip('/')}/recognize"
    req = request.Request(
        url, data=body, headers={"Content-Type": content_type_header}, method="POST"
    )
    start = time.monotonic()
    try:
        with request.urlopen(req, timeout=timeout) as resp:
            latency = time.monotonic() - start
            payload = json.loads(resp.read().decode("utf-8"))
            return {"status": resp.status, "latency": latency, "payload": payload, "error": None}
    except error.HTTPError as exc:
        latency = time.monotonic() - start
        raw = exc.read()
        try:
            detail = json.loads(raw.decode("utf-8")).get("detail", exc.reason)
        except (json.JSONDecodeError, UnicodeDecodeError):
            detail = raw.decode("utf-8", errors="replace") or exc.reason
        return {"status": exc.code, "latency": latency, "payload": None, "error": str(detail)}
    except error.URLError as exc:
        # No HTTP response at all (server down, refused connection, ...).
        latency = time.monotonic() - start
        return {"status": None, "latency": latency, "payload": None, "error": str(exc.reason)}
    except TimeoutError as exc:
        latency = time.monotonic() - start
        return {"status": None, "latency": latency, "payload": None, "error": f"timeout: {exc}"}


# ---------------------------------------------------------------------------
# Run mode
# ---------------------------------------------------------------------------


def _iter_photos(photos_dir: Path) -> tuple[list[Path], list[Path]]:
    """Returns (usable, skipped) sorted for a deterministic run order."""
    usable: list[Path] = []
    skipped: list[Path] = []
    for path in sorted(photos_dir.iterdir()):
        if not path.is_file():
            continue
        ext = path.suffix.lower()
        if ext in _CONTENT_TYPES:
            usable.append(path)
        elif ext in _SKIP_EXTENSIONS:
            skipped.append(path)
    return usable, skipped


def run(photos_dir: Path, base_url: str, hint: str | None, out_path: Path, timeout: float) -> None:
    usable, skipped = _iter_photos(photos_dir)
    for path in skipped:
        print(
            f"SKIP {path.name}: HEIC not usable -- /recognize forwards bytes to "
            "Gemini labeled as image/jpeg regardless of the real format, so a "
            "HEIC upload risks a silent garbage result rather than a clean "
            "failure. Convert to JPEG first."
        )
    if not usable:
        print(f"No jpg/jpeg/png photos found in {photos_dir}", file=sys.stderr)
        sys.exit(1)

    hint_note = f' with hint="{hint}"' if hint else " with NO hint (the PRD's ≥90% claim)"
    print(f"Running {len(usable)} photo(s) against {base_url}{hint_note}")
    print(f"Writing results to {out_path}")
    print()

    latencies: list[float] = []
    confidences: list[float] = []
    succeeded = 0
    failed = 0

    with out_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=CSV_FIELDS)
        writer.writeheader()
        f.flush()

        for path in usable:
            content_type = _CONTENT_TYPES[path.suffix.lower()]
            result = _post_recognize(base_url, path, content_type, hint, timeout)
            latency = result["latency"]
            latencies.append(latency)

            row: dict[str, Any] = {
                "filename": path.name,
                "producer": "",
                "name": "",
                "vintage": "",
                "confidence": "",
                "latency_seconds": round(latency, 3),
                "http_status": result["status"] if result["status"] is not None else "",
                "error": result["error"] or "",
                "verdict": "",
            }

            if result["error"] is None and result["payload"] is not None:
                payload = result["payload"]
                candidates = payload.get("candidates", [])
                confidence = float(payload.get("confidence", 0.0))
                top = candidates[0] if candidates else {}
                row["producer"] = top.get("producer", "")
                row["name"] = top.get("name", "")
                row["vintage"] = top.get("vintage", "") if top.get("vintage") is not None else ""
                row["confidence"] = confidence
                succeeded += 1
                confidences.append(confidence)
                top_label = f"{top.get('producer', '?')} {top.get('name', '?')}".strip()
                print(f"{path.name} -> {top_label or '(no candidates)'}  conf={confidence:.2f}  {latency:.2f}s")
            else:
                failed += 1
                print(f"{path.name} -> FAILED ({result['error']})  {latency:.2f}s")

            writer.writerow(row)
            f.flush()  # incremental: a crash mid-run loses nothing already written

    _print_run_summary(len(usable), succeeded, failed, latencies, confidences)
    print()
    print("Next step -- correctness can only be judged by a human who knows")
    print(f"what's actually in each photo: open {out_path}, fill the `verdict`")
    print("column with y/n per row, then run:")
    print(f"  python3 accuracy_run.py --score {out_path}")


def _print_run_summary(
    total: int, succeeded: int, failed: int, latencies: list[float], confidences: list[float]
) -> None:
    print()
    print("=== Summary ===")
    print(f"Total: {total}   Succeeded: {succeeded}   Failed: {failed}")
    if latencies:
        print(
            f"Latency (s): mean={statistics.mean(latencies):.2f}  "
            f"median={statistics.median(latencies):.2f}  "
            f"min={min(latencies):.2f}  max={max(latencies):.2f}"
        )
    if confidences:
        print("Confidence histogram:")
        counts = {label: 0 for _, _, label in _BUCKETS}
        for c in confidences:
            counts[_bucket_label(c)] += 1
        for _, _, label in _BUCKETS:
            n = counts[label]
            bar = "#" * n
            print(f"  {label:>10}: {n:3d} {bar}")


# ---------------------------------------------------------------------------
# Score mode
# ---------------------------------------------------------------------------


def score(csv_path: Path) -> None:
    with csv_path.open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))

    scored = [r for r in rows if r.get("verdict", "").strip().lower() in ("y", "n")]
    unscored = len(rows) - len(scored)

    if not scored:
        print(
            f"No scored rows in {csv_path} -- fill the `verdict` column with "
            "y/n first (one row per photo)."
        )
        return

    correct = sum(1 for r in scored if r["verdict"].strip().lower() == "y")
    total = len(scored)
    pct = 100 * correct / total
    print(f"Overall: {correct}/{total} correct = {pct:.1f}%")
    if unscored:
        print(f"({unscored} row(s) still unscored -- excluded from this total)")
    print()

    # Calibration check: does stated confidence track actual correctness?
    print("By confidence bucket (checks whether confidence is calibrated):")
    buckets: dict[str, list[bool]] = {label: [] for _, _, label in _BUCKETS}
    unparseable = 0
    for r in scored:
        try:
            conf = float(r["confidence"])
        except (KeyError, ValueError):
            unparseable += 1
            continue
        buckets[_bucket_label(conf)].append(r["verdict"].strip().lower() == "y")

    for _, _, label in _BUCKETS:
        outcomes = buckets[label]
        if not outcomes:
            print(f"  {label:>10}: no rows")
            continue
        n_correct = sum(outcomes)
        n = len(outcomes)
        print(f"  {label:>10}: {n_correct}/{n} correct = {100 * n_correct / n:.1f}%")

    if unparseable:
        print(f"  ({unparseable} row(s) had no usable confidence value, excluded)")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _default_out_path(photos_dir: Path) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    # Sibling of photos_dir, not inside it -- keeps the CSV out of any
    # future re-run's own photo listing.
    return photos_dir.parent / f"{photos_dir.name}_accuracy_{stamp}.csv"


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Run bottle photos through POST /recognize and log results for "
            "scoring the PRD's >=90%% no-hint recognition claim."
        )
    )
    parser.add_argument(
        "photos_dir", nargs="?", type=Path, help="Directory of bottle photos (jpg/jpeg/png/heic)"
    )
    parser.add_argument(
        "--url", default="http://127.0.0.1:8000", help="Pi service base URL (default: %(default)s)"
    )
    parser.add_argument(
        "--hint",
        default=None,
        help="Optional hint form field sent with every photo (default: none, matching the PRD claim)",
    )
    parser.add_argument("--out", type=Path, default=None, help="Override the results CSV path")
    parser.add_argument(
        "--timeout", type=float, default=60.0, help="Per-request timeout in seconds (default: %(default)s)"
    )
    parser.add_argument(
        "--score",
        metavar="CSV",
        type=Path,
        default=None,
        help="Score a previously hand-filled results CSV instead of running new photos",
    )
    args = parser.parse_args()

    if args.score is not None:
        score(args.score)
        return

    if args.photos_dir is None:
        parser.error("photos_dir is required unless --score is given")

    if not args.photos_dir.is_dir():
        parser.error(f"not a directory: {args.photos_dir}")

    out_path = args.out or _default_out_path(args.photos_dir)
    run(args.photos_dir, args.url, args.hint, out_path, args.timeout)


if __name__ == "__main__":
    main()
