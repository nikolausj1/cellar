---
title: "STATUS - Wine Cellar"
created: 2026-07-24
modified: 2026-10-24
version: 1.2
author: Claude Fable 5.1 (claude-fable-5-1)
tags:
---

# Wine Cellar - Status

## Project

Camera-first wine cellar app: point an iPhone (or eventually a Pi-mounted camera) at a bottle label, Gemini identifies it, and the app tracks which fridge slot it's in and when it's ready to drink. iOS app (SwiftUI/SwiftData) plus a Raspberry Pi service, built so the phone works standalone today with zero Pi hardware.

## Stage

Active Development (fridge installed and its layout verified, app deployed to Justin's phone, Gemini key live, and the first real bottle recognized correctly on 2026-10-24; the collection has not been loaded yet)

## Health

🟢 On-track - every blocker from July is cleared: the key is loaded, billing is topped up, and the first real label came back as the right wine at 0.95 confidence. The >=90% accuracy claim is still a sample of one until the pilot shelf runs.

## Waiting on Me

- [ ] **Enter the 14-row layout into Fridge Setup** (~5 min, table in `_review/fridge-geometry.md`)
      - unblocks: placing bottles at their real addresses (A1 to N7)
- [ ] **Pilot one straight shelf through recognition and score it** (~30 min, `pi/tools/accuracy_run.py --score`)
      - unblocks: the go/no-go on the >=90% claim before loading all 120 bottles
- [ ] **Decide where the ~28 overflow bottles live** (~5 min to decide)
      - unblocks: load day; shelves hold 85, the floor row holds a few more but stops the door self-closing
- [ ] **Decide on Gemini auto-reload or a larger prepay** (~2 min, AI Studio billing page)
      - unblocks: nothing today; prevents the API silently stopping at $0 in the middle of a load session
- [ ] **Approve/place the ~$190 Pi parts order in `pi/HARDWARE.md`** (~10 min to decide)
      - unblocks: any physical Pi assembly; nothing purchased yet

## Next Up

1. Enter the layout, start `lab_main.py` from `~/_Developer/Wine Cellar/pi`, point the phone at the Mac.
2. Pilot one straight shelf: load label-up, photograph in place, place each bottle at its letter-number address, score the run.
3. If accuracy holds, load the rest shelf by shelf and greenlight the Pi parts order; if it disappoints, that is a design conversation before any hardware spend.

## Biggest Risk

The >=90% no-hint recognition claim rests on one bottle so far; the pilot shelf is what turns it into a measurement.

---

## Deferred

- The Dropbox copy of this project (`_Projects/Wine Cellar`) is kept untouched as the migration backup; deleting it is a separate decision once the new home has been used for a while
- Floor row N (upright bottles): modeled in the app, not in use yet; bottles there stop the door self-closing
- LCD/display driver for the Pi (`Display` protocol has no real implementation yet, open PRD question)
- Voice notes / microphone (`NullVoiceRecorder` is a deliberate stub)
- Kids' iPad deployment (Ad Hoc/Recipe B), only the adult iPhone has been deployed to
- Any physical Pi assembly, no hardware ordered

## Ideas Shelf

- **Whole-shelf capture** (M) - a pulled-out straight shelf shows every label face-up; one top-down photo could place and recognize seven bottles at once instead of one capture each
- **Kids' iPad deployment** (S) - Ad Hoc/Recipe B rollout so the whole family can browse the cellar
- **Voice notes / microphone** (S-M) - `NullVoiceRecorder` is already a deliberate stub, wiring it up would let tasting notes be captured by voice
- **LCD/display driver for the Pi** (M) - gives the Pi unit its own screen instead of relying on the phone; the `Display` protocol has no real implementation yet

## Lessons

- **A documented `.env` must be loaded by the program, not assumed.** On the Pi, systemd's `EnvironmentFile=` exports `pi/.env`; on the Mac nothing did, so the README's "copy `.env.example` to `.env` and run" recipe failed with a missing-key error on first use. A 20-line stdlib loader in `config.py` (skip comments, strip quotes, never override an existing variable) made the file mean the same thing everywhere. Any project that documents a `.env` and runs outside systemd needs the same. (2026-10-24)
- **Gemini prepaid billing stops silently at $0 with HTTP 402.** The key was valid; the AI Studio project's prepaid account had run dry. Check the balance before suspecting the key. The AI Studio "Buy credits" dialog is a Google Payments iframe whose Continue button did nothing in the normal Chrome profile (no console error, no network call); the purchase went through in an Incognito window. Try Incognito first when a Google payment dialog is inert. (2026-10-24)
- **Simulator UDIDs are not stable.** An Xcode update recreated the simulator set between sessions, so a UDID pinned in notes three months earlier failed with "Invalid device". Resolve the device at run time (`xcrun simctl list devices available`) instead of recording UDIDs in docs or scripts. Pinning by UDID was itself the fix for the earlier trap where a bare device name resolves to `OS:latest`, so the stable recipe is: look up the name you want at run time, then pass the UDID it returns. (2026-10-24)
- **Fixing a leak forward does not scrub it.** Editing a file in a new commit leaves the old content in every earlier commit; before a repo's first push, rewrite history (`filter-branch` or `filter-repo`), delete `refs/original`, expire the reflog, and grep every object for the string. Verified the hard way with a hardcoded home path that survived a fix-forward commit. (2026-07-17)
- **Marking an already-synced Dropbox folder ignored corrupts it.** Setting `com.apple.fileprovider.ignore#P` on a live venv left it missing modules; `.dropboxignore` patterns only govern new matches. After retro-ignoring a dir, delete and recreate it, and expect Dropbox-hosted venvs to need 30 to 60 seconds on a cold start. (2026-07-17)
