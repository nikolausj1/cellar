# Cellar Pi — scan station hardware

Shopping list for the physical scan station described in `hardware.py`:
camera, button, LED, and (for now) nothing else. Prices were checked in
**July 2026** and are approximate — Raspberry Pi board pricing in particular
has moved several times in the last year due to a memory (LPDDR4) supply
shortage; re-check before ordering.

## Parts

| Component | Recommended part | Why this one | Approx. price (Jul 2026) | Where to buy |
|---|---|---|---|---|
| Board | **Raspberry Pi 5 (4GB)** | The code targets "Pi 4/5" (`hardware.py`, `README.md`). Pick the 5: it's the current flagship with the longer support runway, and this service is I/O-bound (camera capture, a JSON queue, HTTP calls out to Gemini) with no local inference, so 4GB is plenty — no need to pay the ~$65 premium for the 8GB board. Board RAM pricing is volatile right now (see note below); check the 8GB price too in case it's ever cheaper than 4GB. | ~$110 | [raspberrypi.com](https://www.raspberrypi.com/products/raspberry-pi-5/) / [PiShop](https://www.pishop.us/product/raspberry-pi-5-4gb/) |
| Camera | **Camera Module 3 (standard, not Wide, not NoIR)** | Autofocus is required — `hardware.py`'s `PiHardware` docstring is explicit that a fixed-focus camera returns an unreadable blur at the ~15cm label distance, and the driver hard-sets continuous AF (`AfMode: 2`). Standard vs Wide: the standard lens' minimum focus distance is ~10cm, comfortably inside the 15cm working distance, and its narrower field of view fills the frame with the label instead of the surrounding shelf — Wide's extra distortion buys nothing here. Skip NoIR: it drops the IR-cut filter, which shifts color balance under normal indoor light and label-color accuracy matters for recognition. | ~$25–29 | [raspberrypi.com](https://www.raspberrypi.com/products/camera-module-3/) / [PiShop](https://www.pishop.us/product/raspberry-pi-camera-module-3/) |
| Camera cable adapter | **22-pin (Pi 5) to 15-pin (camera) FPC cable, 200mm** | Camera Module 3 ships with a 200mm cable terminated for the old 15-pin/1mm-pitch CSI connector used on Pi 4 and earlier. **Pi 5 uses a different, smaller 22-pin/0.5mm-pitch CSI connector** — the cable that comes in the camera box will not plug into a Pi 5. A short adapter cable (15-pin camera end to 22-pin Pi 5 end) is a separate, cheap item — don't forget to add it to the order. If a Pi 4 is used instead, the bundled cable works as-is and this line item is unnecessary. | ~$4 | [PiShop](https://www.pishop.us/product/camera-cable-for-raspberry-pi-5/) / [raspberrypi.com](https://www.raspberrypi.com/products/camera-cable/) |
| Button + LED | **16mm illuminated momentary pushbutton** (integrated switch + LED in one part, 4 leads) | `config.py` wires a single `gpiozero.Button` to GPIO17 and a single `gpiozero.LED` to GPIO27 (`hardware.py`'s `PiHardware.__init__`). An illuminated pushbutton is the simplest part that satisfies both: the switch leads go to GPIO17/GND, the LED leads go to GPIO27/GND via a resistor. A separate button + separate LED works identically if that's easier to source — the code doesn't care, it just needs one momentary switch and one drivable LED. | ~$1.50 | [Adafruit](https://www.adafruit.com/product/1439) |
| microSD card | **32GB, A2/V30-rated** | OS + venv + captured JPEGs + the small JSON queue/candidate files fit comfortably in 32GB with headroom. A2 (fast random I/O) keeps the OS responsive; that mostly matters for boot time and package installs, not the capture pipeline itself. | ~$20 | [raspberrypi.com](https://www.raspberrypi.com/products/sd-cards/) / [PiShop](https://www.pishop.us/product/raspberry-pi-sd-card-32gb/) |
| Power supply | **Official Raspberry Pi 27W USB-C power supply** | Pi 5 is pickier about power than Pi 4 — under-voltage from a generic phone charger shows up as camera/USB instability. The official 27W supply is the vendor-tested match and is inexpensive enough that there's no reason to gamble on a generic one. | ~$14 | [raspberrypi.com](https://www.raspberrypi.com/products/27w-power-supply/) / [Adafruit](https://www.adafruit.com/product/5814) |
| Enclosure | **Official Raspberry Pi 5 case** (or any vented case that leaves the GPIO header and camera connector reachable) | Nothing about this build needs a custom enclosure — any case that (a) doesn't block the camera ribbon route and (b) leaves GPIO17/27 and GND reachable for the button/LED leads works. The official case includes the stock cooling fan, which is worth having since Pi 5 runs warmer than Pi 4 under sustained load. Generic/3rd-party cases are fine too. | ~$11 | [PiShop](https://www.pishop.us/product/raspberry-pi-case-for-pi-5-red-white/) |
| Misc: resistor + hookup wire | 220–1000Ω resistor (for the LED) + a handful of jumper wires | The LED leg needs a series resistor (see wiring note below) — any value in the 220–1000Ω range is fine for a 3.3V GPIO line. A basic resistor assortment or prototyping kit covers this for a couple of dollars. | ~$5 | Adafruit / any electronics stockist |

**Rough total: ~$190–195** (Pi 5 4GB board, camera + adapter cable, button/LED, SD card, official PSU, case, incidentals). Swapping to the 8GB board adds roughly $65; swapping to a Pi 4 instead of a Pi 5 does not currently save money — see the pricing note below.

### A note on board pricing

Raspberry Pi board prices have risen sharply and repeatedly since late 2025 (memory-driven — the Foundation has said LPDDR4 supply costs pushed multiple official price increases through Q4 2025 and Q1 2026). Both major US resellers (PiShop, CanaKit) were pricing the Pi 5 8GB at **~$175** and the Pi 4 8GB at **~$165** as of this check — the two boards are no longer far apart in price the way they used to be, which is part of why Pi 5 is the easy pick here. If ordering later, re-check current prices; the Foundation has said the increases are meant to be temporary as memory supply stabilizes.

## Not needed (yet)

- **LCD/OLED display.** `hardware.py`'s `Display` protocol is intentionally undecided (see the module docstring: "the LCD model is undecided (PRD §12 open question 4)"). Only `ConsoleDisplay` (stdout logging) exists today — there is no driver code for any screen. Don't buy an LCD/OLED until that decision is made and a driver is written; it would sit unused.
- **A HAT or GPIO expansion board.** The only GPIO usage is one button input and one LED output, both wired directly to the header (GPIO17, GPIO27, plus GND). No HAT, breakout board, or expansion header is required.
- **A cooling fan/heatsink as a separate purchase**, if using the official Pi 5 case above — it already includes one. Only add a standalone active cooler if going case-less.
- **An M.2/NVMe HAT or SSD.** Nothing in this service does enough I/O or storage to need it; the microSD card above is sufficient.
- **A microphone.** `hardware.py`'s `NullVoiceRecorder` is a deliberate stub — press-and-hold voice notes are wired end-to-end in the button handler but recording/transcription is explicitly not implemented yet ("Implement once the mic hardware is chosen"). No mic to buy until that's picked up.

## Wiring note

Matches `gpiozero` defaults (active-low button, simple LED sink) and the GPIO pins in `config.py` (`CELLAR_BUTTON_GPIO=17`, `CELLAR_BUTTON_LED_GPIO=27`):

- **Button**: one leg to **GPIO17**, the other leg to **GND**. `gpiozero.Button` enables the internal pull-up by default, so no external resistor is needed — the pin reads high normally and low when pressed.
- **LED**: anode (long leg) through a **220–1000Ω resistor** to **GPIO27**, cathode (short leg) to **GND**. `gpiozero.LED` drives the pin directly (source current when on); the resistor limits current so the GPIO pin and LED aren't damaged.
- If using the combined illuminated-pushbutton part above, its two switch leads go to GPIO17/GND and its two LED leads go to GPIO27/GND-via-resistor exactly as above — it's electrically two separate components in one housing.
