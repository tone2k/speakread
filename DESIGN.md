# Verso — design and build spec

Working name: **Verso** (repo codename: speakread). A recorder that writes down what you say, and a reader that speaks what you read. Built for iPhone Duo, where the fold is the spine of a book.

Design canvas: https://claude.ai/artifact/SbNz7DXvZHtP676Y3quN9t

## 1. The one idea

Speech-to-text and text-to-speech are the same object seen from two sides: **text with a time on every word**. A transcript is timed text produced from audio. A book being read aloud is timed text produced into audio. One data model serves both, so one gesture serves both: tap a word and the sound goes there.

Everything else follows from that:

| Feature | What it is in the model |
|---|---|
| Live transcript | Timed text, appended as audio arrives |
| Marks (chapters in a recording) | Anchors on the time axis |
| Word highlight while a book is read | Timed text, consumed as audio is produced |
| Margin notes | A short timed text pinned to an anchor in a longer timed text |
| "Read my notes back" | Timed text rendered into audio, in the order of its anchors |
| Search | One index across both sides |

## 2. The look: ink, paper, one red ribbon

- **Ground**: Paper `#F7F4EE`, cards `#EDE8DE`, rules `#D9D2C4`. Night: `#0F0E0C`.
- **Ink**: `#1B1915` primary, `#5A554B` secondary (6.5:1 on paper), `#A8A295` only for words that are still settling.
- **Ribbon**: `#C7321F` for surfaces, `#9E2616` for text on paper (7.9:1). Night ember: `#F2603F`.
- **Type**: Newsreader (reading text, headings, the wordmark in italic). SF Pro for controls. SF Mono for time. On the canvas, Inter and IBM Plex Mono stand in for SF.
- **No chrome**: no tab bar, no toolbars with backgrounds. The right-edge rail is bare glyphs. Liquid Glass is used only for the floating transport pill and system sheets, so the paper stays paper.

**The ribbon is the only saturated thing on screen.** It does three jobs:

1. **Bookmark**: on the closed phone it hangs out of the top edge, like a ribbon out of a shut book. It is the whole "now playing" UI. Tap it to continue.
2. **Waveform**: while recording it ripples with your voice.
3. **Playhead**: while listening it lies under the word being spoken, and runs down the spine to your line on the spread.

When nothing is in progress, there is no ribbon.

## 3. Device facts the layout depends on

| Fact | Value | Source |
|---|---|---|
| Inner display | 7.6", 2670 × 1878 px, about 10:7 | Apple, 9to5Mac, MacObserver |
| Inner points | about 669 × 951 pt at 3x (App Store Connect spec) | iphoneduosupport, blakecrosley |
| Outer display | 5.4", 2034 × 1398 px, 466 × 678 pt, same aspect ratio | Apple, codeconfig |
| Hinge | Holds any angle 15°–165°, flat at 180° | BGR review |
| Weight, thickness | 254 g, 5.2 mm open, 11.3 mm closed | MacRumors |
| Crease | Hard to see head-on, can be felt when scrolling | 9to5Mac review |
| Biometrics | Touch ID in the side button | 9to5Mac review |
| Apps on iOS 26 SDK | Letterboxed on the inner display | MacRumors |

Never hardcode the point sizes. Read the view's own bounds and the size classes at runtime.

## 4. Poses and what Verso does in each

| Pose | Size classes | Verso screen | Rule |
|---|---|---|---|
| Closed | compact × regular | Pocket, Recording, Listening, Ears & Voice | One hand. Record button at the bottom center. Ribbon tab at the top. |
| Open wide (fold vertical) | regular × regular | Shelf, Reading spread, Recording spread | Two pages. The division is the spine. Rail on the right edge under the thumb. |
| Open tall (fold horizontal) | regular × regular | Single long page | One column, wide margins, transport at the bottom. |
| Book (partly folded, fold vertical) | regular × regular, division active | Reading spread with margin notes | Gutter widens to division width + 24 pt each side, page shadow appears. Hold the corner to say a note. |
| Laptop (bottom half flat) | regular × regular, division active | Lectern | Content in the upright half, controls in the flat half. Type steps up to 23 pt. |
| Tent | one half visible | Nightstand | Dark paper, ember red, chapter, time left, sleep timer. Tap either half to pause. |

Apple's marketing names five positions (StandBy, landscape, portrait, seated, standing). The developer guide pictures six poses. Verso does not branch on a pose name. It branches on three runtime facts: the size classes, whether a division region is active, and the division's orientation.

## 5. Continuity rules

- Audio never stops because the phone changed shape. One `AVAudioSession` and one playback or capture graph live in a background-capable actor that does not know about views.
- The ribbon never moves without the user. Fold events change layout, never the playhead.
- Closed → open while recording: waveform stays on the left page, transcript spreads to the right page. No reload.
- Open → closed while listening: the outer screen shows the ribbon tab and the current sentence. One tap pauses.
- Open again: the spread is exactly where it was, including scroll position and the current word.
- "Hey Siri, start Verso" starts a recording from any pose via an App Intent.

## 6. Architecture (SwiftUI, iOS 27.1 SDK)

```
VersoApp
├── Engine (actors, no UI)
│   ├── AudioSession          one AVAudioSession, routes, interruptions
│   ├── Capture               AVAudioEngine tap → ring buffer → Ears
│   ├── Ears                  protocol: transcribe(stream) -> AsyncStream<TimedSpan>
│   │   ├── AppleEars         SpeechAnalyzer (on-device, iOS 26+)
│   │   ├── ParakeetEars      Parakeet v3 via CoreML (FluidAudio)
│   │   ├── WhisperEars       WhisperKit
│   │   └── SenseVoiceEars    sherpa-onnx
│   ├── Voice                 protocol: speak(TimedText, from: Anchor) -> AsyncStream<SpokenSpan>
│   │   ├── AppleVoice        AVSpeechSynthesizer, Enhanced voices, Personal Voice
│   │   └── NeuralVoice       on-device neural TTS (Kokoro via MLX), optional download
│   └── Library               SwiftData: Documents, TimedText, Anchors, Notes
├── Importers                 EPUB (Readium), PDF (PDFKit), audio files, Voice Memos share sheet
├── Layout                    FoldState (size classes + reservedRegions) → Pose
└── Screens                   Pocket, Recording, Listening, Settings, Shelf, Reading, RecordingSpread, Lectern, Nightstand, MarginNote
```

### Timed text (the shared model)

```swift
struct TimedSpan: Codable, Hashable {
    var text: String            // one word or punctuation group
    var start: TimeInterval     // seconds from the document's audio origin
    var end: TimeInterval
    var confidence: Float       // 1.0 for book text; < 0.6 renders as "settling"
}

struct TimedText: Codable {
    var spans: [TimedSpan]
    var origin: AudioOrigin     // .recording(fileURL) or .synthesized(voiceID, rate)
}

struct Anchor: Codable, Hashable {
    var spanIndex: Int          // position in the host TimedText
    var kind: Kind              // .mark(label) | .note(TimedText) | .bookmark
}
```

For a recording, Ears fill `spans` as audio arrives. For a book, Voice fills `start`/`end` as it speaks, using `AVSpeechSynthesizer` word-boundary callbacks, so the highlight and the ribbon are driven by the same stream a transcript uses.

### Fold-aware layout

```swift
struct FoldState {
    var horizontal: UserInterfaceSizeClass
    var vertical: UserInterfaceSizeClass
    var division: CGRect?       // from GeometryProxy.reservedRegions(kind: .division)
    var occlusions: [CGRect]    // kind: .occlusion (cameras)

    var pose: Pose {
        guard horizontal == .regular, vertical == .regular else { return .closed }
        guard let d = division else { return .openFlat }
        return d.width < d.height ? .book : .laptop
    }
}
```

- The spread uses `ArrangementView` in split style. Each page is a view. The division becomes the spine.
- The Lectern uses the same `ArrangementView` with the division horizontal: transcript or text on top, transport below.
- Text columns get `padding(.leading/.trailing, division.width / 2 + 24)` on the spine side.
- Nothing interactive is placed inside the division rect. The transport pill is anchored to the right page's leading edge, never centered on the screen.
- The right-edge rail uses the vertical toolbar placement so the system positions it for thumb reach and moves it clear of the hinge.

### Settings: Ears & Voice

The screenshot's model list is kept but reorganized into two plain questions: what turns speech into text (Ears) and what reads text aloud (Voice). Recommended defaults are preselected. Sizes and languages are one line of secondary text. The only switch is "Hey Siri, start Verso". The footer states the privacy promise in one sentence: everything stays on this iPhone, no account, no upload.

## 7. Build plan

Status: steps 1 to 6 are implemented in `Verso.xcodeproj` with Apple's two speech engines. Third-party engines, measured pagination, and the award polish of step 7 remain.

1. **Week 1 · Engine spike.** Timed text model, Capture → AppleEars live stream, AppleVoice with word boundaries. Prove: tap a word in a transcript, audio seeks; tap a word in a chapter, the voice starts there.
2. **Week 2 · Closed screens.** Pocket, Recording, Listening on the outer display. Ribbon tab, record button, background audio, App Intent for Siri.
3. **Week 3 · The spread.** Shelf and Reading spread with `ArrangementView` and reserved regions. EPUB import. Verify in the Xcode 27.1 iPhone Duo simulator, then on hardware.
4. **Week 4 · Recording spread, Lectern, Nightstand.** Pose detection from the division rect. Transcript flows closed → open without a seam.
5. **Week 5 · Margin notes.** Hold the corner, transcribe, pin to the span being read. "Read my notes back" in Personal Voice.
6. **Week 6 · Ears & Voice.** Parakeet, Whisper, SenseVoice downloads. Neural voice download. Settings screen.
7. **Week 7 · Polish for the award bar.** Haptics on the ribbon (a soft tick when it lands on the spine), the unfold animation that reveals the spread through the cover, Dynamic Type, VoiceOver with word-level rotor, reduced motion.

## 8. Open questions for Tony

- Name: Verso, or keep SpeakRead?
- Should margin notes also work on recordings (a note on your own transcript), or only on books?
- Neural voice: ship Apple voices only at first, or include a downloadable neural voice from day one?
