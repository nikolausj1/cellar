# Cellar Pi scan station

Python service that sits between the iPhone app and Gemini, and drives the
physical scan station (camera + button + LCD) once the Pi hardware exists.

The mock and the real service share one set of route handlers
(`cellar_pi/api.py :: create_app`) via dependency injection, so the API
contract cannot drift between "what iOS is built against today" and "what
ships on the Pi later."

```
pi/
  cellar_pi/
    config.py        # env loading, no defaults for secrets
    api.py            # create_app(recognizer, hardware, store) — routes live here ONCE
    recognizer.py      # Recognizer protocol; GeminiRecognizer; MockRecognizer
    hardware.py        # Hardware protocol; PiHardware; MockHardware; Display protocol
    store.py           # outbound queue + candidate list, JSON on disk, atomic writes
    main.py            # real entrypoint: Gemini + Pi hardware
    mock_main.py        # mock entrypoint: stub recognizer + no hardware (runs on the Mac)
    lab_main.py         # lab entrypoint: REAL Gemini recognizer + mock hardware (runs on the Mac)
  systemd/cellar-pi.service
  setup.sh            # idempotent Pi provisioning (run on the Pi only)
  requirements.txt        # real service deps (Pi-only: picamera2, gpiozero, ...)
  requirements-mock.txt   # mock deps (macOS-safe)
  requirements-lab.txt    # mock deps + httpx, no picamera2/gpiozero (macOS-safe)
  .env.example
```

---

## Run the mock on the Mac RIGHT NOW

This is what unblocks iOS today. Zero Pi dependencies, zero API key,
zero network calls.

```bash
cd pi/   # from the repo root

python3 -m venv .venv-mock
source .venv-mock/bin/activate
pip install -r requirements-mock.txt

python -m cellar_pi.mock_main
# Cellar Pi MOCK starting on http://127.0.0.1:8000
```

Leave that running and, from another terminal:

```bash
# Health check
curl -s http://127.0.0.1:8000/health

# Push the phone's cellar list (biases recognition — mock reads it but
# only uses it for hint-matching, see recognizer.py)
curl -s -X PUT http://127.0.0.1:8000/candidates \
  -H 'Content-Type: application/json' \
  -d '{"wines": ["Ornellaia 2015", "Caymus Cabernet 2021"]}'

# Recognize a real photo (any JPEG/PNG works — mock ignores the bytes)
curl -s -X POST http://127.0.0.1:8000/recognize -F "image=@/path/to/bottle.jpg"

# Force each scenario
curl -s -X POST "http://127.0.0.1:8000/recognize?scenario=high" -F "image=@/path/to/bottle.jpg"
curl -s -X POST "http://127.0.0.1:8000/recognize?scenario=low"  -F "image=@/path/to/bottle.jpg"
curl -s -X POST "http://127.0.0.1:8000/recognize?scenario=fail" -F "image=@/path/to/bottle.jpg"
curl -s -X POST "http://127.0.0.1:8000/recognize?scenario=slow" -F "image=@/path/to/bottle.jpg"

# One cached wine-intelligence call
curl -s -X POST http://127.0.0.1:8000/enrich \
  -H 'Content-Type: application/json' \
  -d '{"producer":"Ornellaia","name":"Ornellaia","vintage":2015,"region":"Bolgheri","varietal":"Bordeaux Blend"}'

# Simulate a Pi button press (mock-only route — not in the shared factory)
curl -s -X POST http://127.0.0.1:8000/mock/press
curl -s -X POST "http://127.0.0.1:8000/mock/press?hold=true"   # press-and-hold -> voice note stub

# Drain the queue like the phone would
curl -s http://127.0.0.1:8000/queue
curl -s -X DELETE http://127.0.0.1:8000/queue/<id-from-above>
```

Point the iOS app's Pi base URL at `http://127.0.0.1:8000` (simulator) or
your Mac's LAN IP (device) while the real Pi doesn't exist yet.

---

## Lab mode: real recognition, no Pi

`mock_main.py` is great for iOS plumbing but never calls Gemini —
`MockRecognizer` just rotates canned wines. `lab_main.py` pairs the REAL
`GeminiRecognizer` with `MockHardware`, so you can point the iPhone app at
your Mac and get genuine wine-label recognition without any Pi hardware.
This works because `POST /recognize` reads the photo from the client's HTTP
upload (see `api.py`), not from hardware — mock hardware never limits real
recognition.

```bash
cd pi/   # from the repo root

python3 -m venv .venv-lab
source .venv-lab/bin/activate
pip install -r requirements-lab.txt

cp .env.example .env   # if you don't already have one
# edit .env and set GEMINI_API_KEY (source it from ~/.secrets/api-keys.env
# on the Mac) — never put the real key in any file that gets committed;
# .env is gitignored, .env.example is the committed template

python -m cellar_pi.lab_main
# Cellar Pi LAB starting on http://0.0.0.0:8000 — REAL Gemini recognizer, MOCK hardware.
# Point the iPhone app at: http://<your-mac's-LAN-IP>:8000
```

`lab_main.py` calls `config.require_gemini_key()` just like `main.py`, so a
missing/blank `GEMINI_API_KEY` fails loudly at startup with a clear message
instead of a mysterious 500 on the first `/recognize` call.

```bash
curl -s http://127.0.0.1:8000/health
# {"ok":true,"hardware":"mock","recognizer":"gemini","queued":0}

curl -s -X POST http://127.0.0.1:8000/recognize -F "image=@/path/to/bottle.jpg"
# a real Gemini call, real candidates
```

**LAN exposure — read before running.** Unlike `mock_main.py` (which
hardcodes loopback deliberately, see "Deviations from spec" below),
`lab_main.py` binds `config.host`, which defaults to `0.0.0.0` — a
LAN-reachable address, not loopback. That's the point: an iPhone on the
same WiFi needs to reach it directly, with no Pi in between. But there is
**no authentication** on this server — anyone on the same network can hit
`POST /recognize` and spend your Gemini quota. This is a lab/dev tool for a
trusted home network, not a deployment; don't run it on untrusted WiFi and
don't leave it running unattended for long stretches. `lab_main.py` logs
its best-effort-detected LAN IP(s) on startup so you can type the URL into
your phone without hunting for it.

---

## Measuring recognition accuracy

The PRD's riskiest claim is "≥90% of bottles recognized correctly with no
hint." `pi/tools/accuracy_run.py` is a stdlib-only script (no venv, no
`pip install` — run it with bare `python3`) that batches real
`POST /recognize` calls against whatever service is running (mock, lab, or
the real Pi) and logs results to a CSV. Scoring correctness is left to a
human on purpose — only the owner knows what each bottle actually is.

```bash
# 1. Point it at a directory of bottle photos and a running service.
#    Default: no hint, matching the PRD's claim. Writes a CSV next to the
#    photos dir, one row per photo, written incrementally so a crash
#    partway through a 120-bottle run loses nothing already done.
python3 pi/tools/accuracy_run.py ~/Desktop/bottle-photos --url http://127.0.0.1:8000

# 2. Open the CSV, fill the empty `verdict` column with y/n per row (only a
#    human can judge whether the top candidate is actually right), then
#    score it:
python3 pi/tools/accuracy_run.py --score ~/Desktop/bottle-photos_accuracy_<timestamp>.csv
# Overall: 108/120 correct = 90.0%
# By confidence bucket (checks whether confidence is calibrated): ...
```

HEIC photos are skipped with a warning: `GeminiRecognizer` always tells
Gemini the bytes are `image/jpeg` (`recognizer.py`) regardless of the real
format, so a HEIC upload risks a silent garbage result rather than a clean
failure — convert to JPEG first. Pass `--hint "some word"` to run the
hint-assisted path and compare it against a no-hint run.

---

## Deploy later: the real Pi runbook

Parts required: Pi 4 or 5, Camera Module 3 (autofocus — non-negotiable,
see `hardware.py`'s `PiHardware` docstring), momentary button, illuminated
LED, SPI LCD (model TBD — see PRD §12 Q4; `ConsoleDisplay` is a stand-in
until then).

1. **Get the repo onto the Pi** (Build Guide deployment workflow):
   ```bash
   ssh pi@<pi-hostname> "git clone <repo-url> ~/cellar-pi"
   ```
   or `git pull` if it's already there.

2. **Run setup.sh** (idempotent — safe to re-run after every `git pull`):
   ```bash
   ssh pi@<pi-hostname>
   cd ~/cellar-pi/pi
   ./setup.sh
   ```
   This installs apt deps (`python3-picamera2`, etc.), creates
   `.venv` with `--system-site-packages` (so it can see picamera2, which is
   apt-only and not on PyPI), installs `requirements.txt`, copies
   `.env.example` → `.env` if `.env` doesn't exist yet, and installs +
   enables the systemd unit.

3. **Fill in `.env`** on the Pi (never commit it):
   ```bash
   nano ~/cellar-pi/pi/.env
   # GEMINI_API_KEY=<from ~/.secrets/api-keys.env on the Mac>
   # confirm CELLAR_BUTTON_GPIO / CELLAR_BUTTON_LED_GPIO match the wiring
   ```

4. **Start it:**
   ```bash
   sudo systemctl start cellar-pi
   sudo systemctl status cellar-pi     # should be "active (running)"
   journalctl -u cellar-pi -f          # tail logs; confirms the button armed
   ```
   If `GEMINI_API_KEY` is missing or blank, the service refuses to start
   and `systemctl status` shows the failure immediately — it will not come
   up half-working and fail mysteriously on the first scan.

5. **Redeploy after a change:**
   ```bash
   ssh pi@<pi-hostname> "cd ~/cellar-pi && git pull origin main && cd pi && ./setup.sh && sudo systemctl restart cellar-pi"
   ```

### Reachability: Tailscale Serve

Run the Pi on your tailnet and use **Tailscale Serve** to expose it over
real HTTPS on its `*.ts.net` name, rather than plain HTTP on the LAN:

```bash
sudo tailscale up
sudo tailscale serve --bg 8000
tailscale serve status
```

This gives you a trusted `https://<pi-name>.<tailnet>.ts.net` endpoint with
a real certificate. That matters specifically because **iOS App Transport
Security (ATS) requires HTTPS with a valid cert by default** — hitting the
Pi over plain `http://` from the phone would otherwise require an ATS
exception (`NSAllowsArbitraryLoads` or a per-domain carve-out) in
`Info.plist`, which the Build Guide steers away from. Tailscale Serve
avoids that entirely: the iOS app just talks to the `.ts.net` HTTPS URL
like any other trusted host, reachable from home or a wine store, no open
ports anywhere (PRD §9).

### Verifying the real service end to end

```bash
curl -s https://<pi-name>.<tailnet>.ts.net/health
# {"ok":true,"hardware":"pi","recognizer":"gemini","queued":0}

curl -s -X POST https://<pi-name>.<tailnet>.ts.net/recognize -F "image=@bottle.jpg"
# a real wine, from a real Gemini call
```

Press the physical button → LCD (console log, until the real LCD lands)
should show `Capturing…` then `✓ <wine>` or `? Logged, needs review` or
`⚠ offline, queued` within a few seconds → `GET /queue` shows the entry →
phone drains it → `DELETE /queue/{id}` acks it.

---

## Config reference (`.env`)

See `.env.example` for the authoritative list. Highlights:

- `GEMINI_API_KEY` — required by the real service only; no default, fails
  loudly at startup if missing (`config.py :: require_gemini_key`).
- `CELLAR_CONFIDENCE_THRESHOLD` (default `0.85`) — decides the Pi's LCD
  `✓` vs `? needs review` display only. It never rejects a scan; low
  confidence still logs (PRD §5, §6.5).
- `CELLAR_BUTTON_GPIO` / `CELLAR_BUTTON_LED_GPIO` — set once parts are
  wired up.
- `CELLAR_DATA_DIR` — where `queue.json`, `candidates.json`, and captured
  JPEGs live. Survives restarts; `.dropboxignore` already excludes
  `captures/`.

---

## Deviations from spec, and why

- **`requirements-mock.txt` includes `python-multipart`**, not just
  `fastapi`/`uvicorn`/`pydantic`. `POST /recognize` is a genuine multipart
  file upload (`image` field) with form fields (`hint`, `scenario`) per the
  API contract; FastAPI/Starlette raise at request time without
  `python-multipart` installed — there's no way to serve that endpoint
  without it. Verified: without it, `/recognize` 500s with "Form data
  requires python-multipart to be installed"; with it, the endpoint works
  as specified. No other extra packages were added.
- **`capture_and_enqueue()` lives in `api.py`, not as a route.** The spec's
  file tree doesn't list a dedicated module for the button-press pipeline
  (capture → recognize → enqueue → update the LCD), and it's exactly as
  shared as the routes are — both `main.py`'s real GPIO callback and
  `mock_main.py`'s `POST /mock/press` call it. Putting it in `api.py`
  keeps it next to the logic it mirrors instead of inventing a new file.
- **`PUT /candidates` and `DELETE /queue/{id}` return `{"ok": true}`** —
  the spec defines `/recognize`, `/enrich`, `/queue`, and `/health`
  response bodies exactly but doesn't specify these two. `{"ok": true}`
  matches the shape already used elsewhere in the contract.
- **Mock binds `127.0.0.1`, not `CELLAR_HOST`'s default `0.0.0.0`.**
  `.env.example` defaults `CELLAR_HOST=0.0.0.0` for the Pi's benefit (LAN +
  Tailscale reachability). Binding a mock dev server to `0.0.0.0` on a
  laptop would expose it to the whole LAN by accident, so `mock_main.py`
  hardcodes loopback regardless of `.env`.
