# Cellar

A wine collection that catalogs itself. Point a camera at a bottle, put the bottle
in the fridge, and never type a word.

An iPhone app (SwiftUI + SwiftData) plus a Raspberry Pi scan station that reads
wine labels with a frontier vision model. Personal project, built for one fridge.

## Status

Honest state of things:

- **iOS app** — builds and runs. Fridge map, shelf setup, add and bulk-add flows,
  slot picker, review queue.
- **Pi service** — works. Real Gemini recognition is reachable today from a laptop
  with no Pi hardware (see *Lab mode*).
- **Recognition accuracy** — **unvalidated.** The design assumes a vision model can
  identify a wine label from a single photo with no hint. That assumption has not
  been measured against real bottles yet. It is the biggest open risk in the project.
- **Hardware** — does not exist. No Pi, no camera, no button. The service's hardware
  layer is behind a protocol, and only the mock implementation has ever run.

## Why it looks like this

The design is shaped by two facts about a real wine fridge:

**Bottles are stored neck-out.** A photo of a shelf shows a dozen foil capsules, not
labels. So there is no multi-bottle "scan the whole shelf" feature, and no AR overlay
through the glass — you cannot identify a wine from a picture of its capsule. Bottles
are recognized one at a time, label-first, on the way in.

**No open wine-label database exists.** Vivino, CellarTracker and Wine-Searcher have no
public APIs, and building an image-embedding corpus is a bigger project than this app.
A frontier vision model already knows what wine labels look like, so the model *is* the
database.

## The one invariant

**Capture never blocks.** When a bottle is photographed it occupies its slot in the
fridge map *immediately* — before recognition returns, and whether or not recognition
ever returns. The label lookup happens asynchronously and reconciles later; anything it
can't resolve lands in a review queue.

This matters on load day, when a case of twelve is going in and nobody wants to wait on
a network round-trip per bottle. It's verified against a server forced to a five-second
delay: the bottle is on the map four seconds before the recognizer answers.

## Layout

```
Cellar/                 iOS app (XcodeGen — project.yml is the source of truth)
  Sources/Engine/       pure logic: layout, readiness, audit diff, cellar value
  Sources/Models/       SwiftData models
  Sources/Services/     Pi client, recognition queue, persistence
  Sources/Views/        map, setup, add flows, review queue
  Tests/SmokeTest.swift engine tests (see below)
pi/                     Raspberry Pi service (FastAPI)
  cellar_pi/api.py      routes — identical contract across all three entrypoints
  cellar_pi/main.py     real:  Gemini recognizer + Pi hardware
  cellar_pi/lab_main.py lab:   Gemini recognizer + mock hardware  (runs on a Mac)
  cellar_pi/mock_main.py mock: mock recognizer  + mock hardware  (no key, no network)
```

The recognizer and the hardware are injected separately, which is what makes lab mode
possible: `POST /recognize` takes its image from the client's upload rather than from a
camera, so real recognition doesn't need real hardware.

## Running it

The `.xcodeproj` is generated and gitignored:

```bash
cd Cellar && xcodegen generate
open Cellar.xcodeproj
```

**Mock mode** — no API key, no network, nothing to configure. This is enough to work on
the iOS app:

```bash
cd pi/
python3 -m venv .venv-mock && source .venv-mock/bin/activate
pip install -r requirements-mock.txt
python -m cellar_pi.mock_main       # 127.0.0.1:8000
```

**Lab mode** — real Gemini recognition, no Pi. Needs `GEMINI_API_KEY` in `pi/.env`
(copy `pi/.env.example`). Binds a LAN address on purpose so a phone can reach it, and
has **no authentication** — a tool for a trusted home network, not a deployment:

```bash
cd pi/
python3 -m venv .venv-lab && source .venv-lab/bin/activate
pip install -r requirements-lab.txt
python -m cellar_pi.lab_main        # prints the URL to enter in the app
```

Then point the app at it: **Fridge Setup → Scan station**.

## Engine tests

The engine is plain Foundation — no Xcode, no XCTest, no SwiftData — so it tests with
`swiftc` directly:

```bash
cd Cellar
T=$(mktemp -d) && xattr -cr Sources && cp Tests/SmokeTest.swift "$T/main.swift" && \
  swiftc -O Sources/Engine/*.swift "$T/main.swift" -o "$T/t" && "$T/t"; rm -rf "$T"
```

Currently 113 assertions. The private temp dir is deliberate — a shared `/tmp` path lets
two projects clobber each other and report a green run against the wrong code.

## License

MIT — see [LICENSE](LICENSE).
