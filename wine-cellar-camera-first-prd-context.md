# Wine Cellar App — Camera-First Product Requirements Document

## Document Status

This PRD captures only the concepts stated in the source conversation. Where the conversation does not provide enough information, the decision or context is explicitly marked as unresolved.

## Product Vision

The wine fridge is a living collection and a timeline of future experiences, not a spreadsheet or inventory database.

The app should make owning and managing wine enjoyable through a beautiful digital version of the user's actual wine fridge or cellar. The core experience is centered on a visual, interactive replica of the physical fridge rather than lists, search, or forms.

The intended collection loop is:

1. Buy a bottle and add it in seconds.
2. Place it on its virtual shelf.
3. Get suggestions for when to drink it.
4. Record the meal, occasion, and memories when it is opened.
5. Build a history of the collection over time.

## Core Product Goal

Manage a wine collection without typing.

The phone's camera is the primary input device. Building and maintaining a digital wine cellar should take less than 30 seconds per bottle with virtually no typing.

Common actions should begin with the camera:

- Add a bottle by pointing the camera at it.
- Remove a bottle by pointing the camera at it.
- Move a bottle by pointing the camera at it.
- Identify a bottle while it is still lying in the fridge.
- Browse the cellar by visually scanning shelves.

If the user has to manually search for a wine such as “Silver Oak Cabernet 2019,” the intended camera-first experience has failed.

## Primary Stocking User Story

> I just bought twelve bottles from Total Wine. I walk over to my wine fridge and point my phone at each bottle. The app recognizes each one immediately, asks which shelf I placed it on, and I am done.

## Label Recognition Pipeline

Label recognition should use more than OCR alone.

### 1. Bottle Detection

Use Apple's Vision framework to detect:

- Bottle boundaries
- Bottle orientation
- Multiple bottles in one image

### 2. Label OCR

Read the label and extract:

- Winery
- Wine name
- Vintage
- Region
- Appellation
- Producer

### 3. Visual Matching

Because many labels do not OCR well, generate an image embedding of the label and compare it against a wine database.

Visual matching is intended to support recognition when labels contain:

- Handwritten fonts
- Decorative typography or artwork
- Angled bottles
- Partially obscured content

### 4. AI Verification

Provide the image and OCR result to an LLM. The returned result should include:

```text
Confidence: 99%

Wine:
Caymus Cabernet Sauvignon

Vintage:
2021

Region:
Napa Valley

Bottle Size:
750ml
```

### 5. Confidence-Based Confirmation

Only require user confirmation when confidence is low.

The confirmation experience should present the proposed identification and offer:

- Yes
- No

The definition of “low confidence” is unresolved.

## Multi-Bottle Recognition

The app should support identifying multiple bottles from a single photo of a shelf rather than requiring every bottle to be scanned individually.

Example result:

```text
Shelf 2

✓ Silver Oak 2019
✓ Duckhorn Merlot
✓ Stag's Leap Cabernet
✓ Ridge Zinfandel
✓ Cakebread Chardonnay

Detected 12 bottles
```

The user can tap **Save** to add the recognized bottles. The intended benefit is reducing the time needed to stock a shelf from several minutes to approximately 30 seconds.

## Cellar Sync

The app should remember which bottles are expected on each shelf. When the user scans a shelf again, the app should reconcile the new scan against the saved shelf state.

The reconciliation can identify:

```text
Missing
• Caymus Cabernet

New
• Jordan Cabernet

Moved
• Ridge Zin
```

When a bottle is missing, the app should ask what happened and offer:

- Drank it
- Moved it
- Gifted it
- Sold it

## Camera-Based Bottle Removal

The removal flow should avoid searching for a bottle and deleting it through a list.

1. Open the app.
2. The camera opens immediately.
3. Point the camera at a bottle.
4. The app identifies the bottle and shows its current shelf and position.
5. Choose an outcome.

Example:

```text
Silver Oak 2019

Currently:
Shelf C
Position 8

Remove?

[Drink]
[Gift]
[Broken]
[Move]
```

## Camera-Based Bottle Move

A user should be able to begin a move by pointing the camera at a bottle. The app identifies the bottle and allows it to be assigned to a new shelf or location.

The conversation does not define the complete move interaction, including how the destination is selected or confirmed.

## Label Changes Across Vintages

Wine labels may change between vintages, so visual matching should not require an exact image match.

Matching should prioritize:

- Producer
- Artwork
- Typography
- Logo
- Bottle shape

## Fallback Recognition Flow

When a label cannot be read or confidently matched, the fallback order is:

1. OCR
2. Image matching
3. The user types one word

For example, entering `Duck...` should allow AI to narrow the possible match.

What happens if this fallback still does not identify the bottle is unresolved.

## Future: Fridge-Layout Recognition

In a future version, the user scans the wine fridge and computer vision determines the shelves and approximate bottle positions.

Example shelf representation:

```text
🍷🍷🍷🍷🍷🍷
🍷🍷🍷🍷🍷🍷
```

The goal is for the digital cellar to update automatically without requiring the user to drag bottles into place.

## Design Principle: Camera First

The camera is the primary navigation method throughout the app. Users should be able to perform almost every common task by pointing the phone at a bottle.

### Supported Camera Actions

| Action | Camera behavior |
| --- | --- |
| Add bottle | Recognize the label and create an inventory record. |
| Remove bottle | Recognize the label and remove it from inventory. |
| Move bottle | Recognize the label and assign it to a new shelf or location. |
| Inventory shelf | Detect multiple bottles and reconcile differences. |
| View bottle | Display tasting notes, purchase history, drink window, and personal memories. |
| Recommend bottle | Point at a shelf and highlight bottles that are at peak drinking age. |

## Future/Defining Concept: Live Cellar Mode

Live Cellar Mode keeps the camera open and places an augmented-reality overlay on the physical wine fridge.

As the user points the camera at the fridge, recognized bottles are outlined with overlays showing:

- Name
- Vintage
- Drink readiness
- Remaining bottle count

Outline colors communicate readiness:

- Green: in the ideal drinking window
- Yellow: hold
- Red: drink soon

This mode turns the physical cellar into an interactive interface rather than requiring the user to navigate menus. It is described as the defining experience that users may remember and share with others.

## Existing Scope and Phase Distinctions

The source conversation proposes the following phases.

### Phase 1 — Two to Three Weekends

- Scan wine labels with Vision OCR
- Use AI to extract winery, vintage, varietal, and region
- Interactive fridge layout
- Add and remove bottles
- Search and filter
- Drink history

### Phase 2

- AI tasting notes
- Pairing engine
- Drink-window predictions
- Smart recommendations
- Statistics

### Phase 3

- Family sharing
- Apple Watch support
- Siri shortcuts
- Shopping mode
- Restaurant wishlist
- Cellar valuation
- Barcode and NFC support

Multi-bottle recognition, Cellar Sync, fridge-layout recognition, and Live Cellar Mode are described elsewhere in the conversation but are not assigned to a numbered phase. Their phase placement remains unresolved.

## Unresolved Decisions and Missing Context

The source conversation does not resolve the following:

- The product name.
- The target iOS version and supported iPhone hardware.
- The source, ownership, coverage, or access model for the wine database used in visual matching.
- The image-embedding model or service.
- The LLM or service used for AI verification.
- Whether recognition processing occurs on-device, remotely, or through a combination of both.
- The confidence threshold that triggers user confirmation.
- How confidence is calculated across bottle detection, OCR, visual matching, and AI verification.
- What the user sees or does after selecting **No** on a proposed identification.
- What happens when OCR, image matching, and the one-word fallback all fail.
- How multiple identical bottles are distinguished, counted, or reconciled.
- How the destination shelf or position is selected and confirmed during a move.
- How shelf identities and physical positions are initially defined.
- How conflicts or mistakes in Cellar Sync reconciliation are corrected.
- How partial visibility, glare, low light, occlusion, and bottles stored with labels facing away are handled.
- How bottle size is detected or verified.
- How users review or correct extracted wine details before saving.
- Whether Live Cellar Mode is part of a numbered phase.
- Whether multi-bottle recognition and Cellar Sync are part of the first release or a later phase.
- Privacy, data retention, account, sharing, and offline behavior.
- The source and method for tasting notes, drinking windows, pairings, recommendations, and cellar valuation.
- Acceptance criteria and validation methods for recognition accuracy, stocking time, and reconciliation behavior.

