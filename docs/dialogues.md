# Dialogues: hear Plato performed

Status: phases 1 to 3 of the build order are implemented. A dialogue imports with its cast, both engines read one voice per character with a breath between turns, and the Cast sheet, speaker labels, line skipping and the laptop-pose stage are in the app. A bundled Euthyphro sample seeds the shelf. Remaining: Foundation Models attribution for unlabeled texts, Read with me, and the optional cloud performance.

## The intent, in one sentence

A dialogue is a book where the words already know who says them, so Verso should read it the way a cast reads a play: one voice per character, a breath between turns, and the ribbon under the line being spoken.

## The decision: offline first, and offline is enough

Every part of the core loop runs on the phone.

| Part | How, offline | Quality |
|---|---|---|
| Who says what | A parser for speaker labels (`SOCRATES:`, `Phaedr.`, `Socrates.`). Plato in the Jowett translations on Project Gutenberg uses these forms. | Exact for scripts and dialogues |
| Hard cases (novels with quoted speech, no labels) | Apple's on-device Foundation Models framework (iOS 26+), asked to attribute each quote to a named speaker, with guided generation so the answer is typed, not prose | Good, improves with the model |
| Voices | Apple's Enhanced and Premium voices, several per language, plus per-character pitch and pace | Clear and distinct, same as the book reader today |
| Better voices (next) | A small neural voice model on the phone (Kokoro-class, about 80 MB, Apache 2.0), with a handful of named voices | Natural, expressive, still offline |
| Word tracking | The same `TimedText` and the same ribbon | Identical to books |
| Read with me (you play a part) | SpeechAnalyzer listens for your line and continues when you finish | Offline |

The cloud is optional and only for one thing: a premium **performance**. A cloud voice renders the whole dialogue to audio with word timestamps. That result is a `TimedText` with an audio file, which is exactly a Verso recording, so the `Player` plays it with no new code. The cloud is a plug-in at the edge, never in the loop.

Why not cloud by default: it costs per word, it needs a network on a device that lives in a pocket, it sends the text off the phone, and it breaks the promise on the Settings page. Apple's voices are already good enough for a first listen, and a neural model on the phone closes most of the gap.

## How it works

### 1. Import

Drop in an EPUB, PDF, or plain text. The EPUB and PDF importers already produce chapters of text. A new pass, `DialogueParser`, runs over every chapter.

- It collects every paragraph that starts with a label: ALL CAPS followed by a colon or period, Title Case followed by a colon, or a short abbreviation with a period.
- A label counts only if it appears three times or more. The chapter is a dialogue if two or more labels survive and they open at least a third of the paragraphs. That keeps "Mr." and "Dr." from becoming characters, and leaves Jowett's long introductions as narration.
- The chapter text is rebuilt with the labels removed, so the voice never reads "SOCRATES:". Each paragraph becomes a `Turn` with a speaker and a span range. Unlabeled paragraphs are narration.

### 2. The cast

When at least one chapter is a dialogue, the document gets a `Cast`: one `CastMember` per speaker, in order of first appearance, plus Narrator.

- Each member has a voice identifier, a pitch, and a pace. Verso assigns distinct Apple voices round-robin from the Enhanced and Premium voices for the language, Narrator gets the reader's usual voice, and later members get small pitch and pace offsets so even two members sharing a voice sound different.
- A Cast sheet lists the members. Tap one to pick a voice, nudge pitch and pace, and hear a sample line from the text. The sheet opens on its own the first time a dialogue is opened.

### 3. Performance

The `Reader` already speaks one utterance per chapter and maps word boundaries back to spans. For a dialogue it speaks one utterance per turn.

- Each utterance carries its member's voice, pitch and rate, and a post-utterance delay of about half a second, so turns breathe.
- A table from utterance to span base keeps the word highlight correct across turns.
- Play, pause, skip, tap-a-word and the ribbon work unchanged. Skip moves by turns, not seconds, which is what you want in a dialogue.

### 4. On the Duo

- **Closed:** the Listening screen shows the current turn with the speaker's name as a small-caps kicker above it, and the next speaker's name faintly below.
- **Open flat:** the spread reads like a playscript. Speaker names sit in the outer margin in ribbon red, the way timestamps sit beside a transcript.
- **Laptop pose:** the stage. The text is on the upright half. The flat half shows the cast as a row of name cards, and the card of whoever is speaking lifts and lights. Tap a card to jump to that character's next line.
- **Book pose:** cast on the left page, dialogue on the right.

### 5. Read with me (phase 3)

Pick a character in the Cast sheet and mark "I'll read this part". From then on:

- Verso reads every other turn aloud.
- At your turn, the ribbon stops at your first word, the phone listens, and the live transcript appears under the line as you speak, so you can see yourself keep up.
- When you stop for about a second, Verso continues with the next speaker.
- A recording of your turns is kept as a Verso recording, pinned to the dialogue, so you can hear yourself as Phaedrus later.

This is where the two halves of Verso meet. Said and Read become one activity.

## Data model changes

```swift
struct Turn: Codable, Hashable {
    var speaker: String?      // nil = narration
    var start: Int            // first span index in the chapter
    var end: Int              // one past the last
}

struct Chapter: Codable, Hashable {
    var title: String
    var text: String
    var turns: [Turn]? = nil  // present when the chapter is a dialogue
}

struct CastMember: Codable, Hashable, Identifiable {
    var id: String            // the speaker label as parsed
    var name: String          // display name, editable
    var voiceIdentifier: String?
    var pitch: Double         // 0.5 ... 2.0, default 1
    var pace: Double          // multiplier, default 1
    var readByMe: Bool        // phase 3
}

struct Cast: Codable, Hashable {
    var members: [CastMember]
}
```

`Document` gains `castData: Data?`. Old books decode unchanged because `turns` and `castData` are optional.

## Build order

1. **Parser and cast model.** Done: `Verso/Model/Dialogue.swift`. Plain-text import with Gutenberg boilerplate stripping: `Verso/Import/TextImporter.swift`.
2. **Reader: chunks never cross a turn, each chunk carries its speaker.** Done. Apple path: the member's voice, pitch and pace per utterance, `postUtteranceDelay` at the end of a turn. Kokoro path: the member's Kokoro voice and speed per chunk, with the breath baked into the buffer as silence so it pauses with the audio.
3. **Cast sheet, speaker labels, line skipping, laptop-pose stage.** Done: `Verso/Screens/CastView.swift`. The sheet opens on its own the first time a dialogue is opened.
4. **Foundation Models attribution** for texts without labels, behind a "Find the speakers" button, so it never runs without asking.
5. **Neural on-device voice** as a second `Voice` engine, downloadable from Ears & Voice.
6. **Read with me.**
7. **Cloud performance** as an optional engine that renders to a recording.

## Test texts

Project Gutenberg, Jowett translations: Phaedrus, Symposium, Euthyphro, Apology, Crito. Phaedrus and Euthyphro use `SOCRATES:` and `PHAEDRUS:` labels after a long introduction, which is the exact shape the parser expects. Apology is a monologue and should import as a plain book, which is the negative test.
