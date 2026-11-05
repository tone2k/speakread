# Verso

**Say it. Read it. One red ribbon marks your place.**

Verso is a recorder that writes down what you say, and a reader that speaks what you read. It is designed for iPhone Duo, where the fold is the spine of a book. Everything runs on the phone: no account, no upload.

<p align="center">
  <img src="docs/screenshots/Main.png" alt="Verso brand board: wordmark, palette, type, and the three jobs of the ribbon" width="100%">
</p>

- **Design canvas (interactive, with notes):** https://claude.ai/artifact/SbNz7DXvZHtP676Y3quN9t
- **Build spec:** [DESIGN.md](DESIGN.md) covers the data model, architecture, pose rules, and the build plan.
- **Artboard sources:** [design/canvas](design/canvas). Re-render the screenshots with `node design/render.mjs`.

## The one idea

Speech-to-text and text-to-speech are the same object seen from two sides: text with a time on every word. A transcript is timed text made from audio. A book read aloud is timed text made into audio. One data model serves both, so one gesture serves both. Tap a word, and the sound goes there.

## Closed · 5.4-inch outer display

One hand, one thumb. The ribbon hanging from the top edge is the whole "now playing" interface. It is a ribbon out of a shut book: tap it to pick up where you left off. The record button is where the thumb already rests.

<p align="center">
  <img src="docs/screenshots/Pocket.png" alt="Pocket: the closed home screen with the ribbon tab, Said and Read tabs, recent recordings, and the record button" width="24%">
  <img src="docs/screenshots/Recording.png" alt="Recording on the closed phone: timecode, ribbon waveform, live transcript with settling words" width="24%">
  <img src="docs/screenshots/Listening.png" alt="Listening on the closed phone: the current sentence with the spoken word highlighted, ribbon progress, transport" width="24%">
  <img src="docs/screenshots/Settings.png" alt="Ears and Voice settings: speech-to-text engines and reading voices" width="24%">
</p>

## Open flat · 7.6-inch inner display

The fold is the spine. The two tab words on the closed phone, Said and Read, become the two page headings when the phone opens. Nothing interactive ever sits on the crease. The control rail lives on the right edge, under the thumb.

<p align="center">
  <img src="docs/screenshots/Shelf.png" alt="The Shelf: Said on the left page lists recordings, Read on the right page shows books, with a rail on the right edge" width="100%">
</p>

<p align="center">
  <img src="docs/screenshots/Reading.png" alt="Reading spread: two pages of a book, the ribbon runs down the spine to the line being read, the spoken word is highlighted" width="100%">
</p>

<p align="center">
  <img src="docs/screenshots/RecordingSpread.png" alt="Recording spread: waveform, timecode, and marks on the left page, the live transcript on the right page" width="100%">
</p>

## Half-folded poses

The hinge holds any angle from 15 to 165 degrees. Verso does not branch on a pose name. It reads three runtime facts: the size classes, whether a fold region is active, and which way the fold runs.

| Laptop pose · Lectern | Tent pose · Nightstand |
|---|---|
| <img src="docs/screenshots/Lectern.png" alt="Lectern: the transcript in the upright half, large controls in the flat half" width="100%"> | <img src="docs/screenshots/Nightstand.png" alt="Nightstand: dark paper, ember red, book title, time left, sleep timer, and a pause button" width="100%"> |
| Text rises to the upright half, large enough to read across a table. Controls drop to the flat half where fingers rest. | Dark paper, ember red, the chapter and a sleep timer. A tap on either half pauses. |

<p align="center">
  <img src="docs/screenshots/MarginNote.png" alt="Book pose: a wider gutter, red knots in the margin for earlier notes, and a note being spoken and pinned to the sentence being read" width="100%">
</p>

**Book pose · Margin note.** This is where recorder and reader meet. Hold the corner, speak, let go. The note is transcribed on the phone and pinned to the sentence being read, marked by a small red knot in the margin. Later, "Read my notes back" plays your notes in your own Personal Voice, in book order.

## Continuity

The phone changes shape. Verso keeps its place. Sound never stops, and the ribbon never moves without you.

<p align="center">
  <img src="docs/screenshots/Flow.png" alt="Six moments of continuity: open it, keep talking, close it, set it down, stand it up, half-fold" width="100%">
</p>

## The look

- **Ink on paper.** Paper `#F7F4EE`, ink `#1B1915`, cards `#EDE8DE`. Night mode uses `#0F0E0C` with ember `#F2603F`.
- **One accent.** Ribbon red `#C7321F` is the only saturated color on screen. It is the bookmark when closed, the waveform when recording, and the playhead when listening.
- **Type.** Newsreader for reading text and headings, SF Pro for controls, SF Mono for time. The renders use Inter and IBM Plex Mono in place of SF.
- **No chrome.** No tab bar, no toolbar backgrounds. Liquid Glass appears only on the floating transport pill and system sheets.

## Engines

| Ears (speech to text) | Voice (text to speech) |
|---|---|
| Apple SpeechAnalyzer, Parakeet v3, Whisper, SenseVoice | Apple Enhanced voices, Personal Voice, optional on-device neural voice |

All engines run on the phone. Downloads are optional and listed with their size and languages.

## Rendering the screenshots

```
node design/render.mjs
```

Needs Node 22 and Playwright with Chromium. If Playwright is installed globally, run with `NODE_PATH=$(npm root -g)`.
