import Foundation

/// One speaker's turn in a chapter, as a range of span indices.
struct Turn: Codable, Hashable {
    /// Nil means narration or stage direction.
    var speaker: String?
    var start: Int
    var end: Int

    var range: Range<Int> { start..<end }
}

/// A character in a dialogue and how Verso voices them.
struct CastMember: Codable, Hashable, Identifiable {
    /// The speaker label as parsed, e.g. "SOCRATES". Stable across edits.
    var id: String
    var name: String
    /// An Apple voice identifier, used when the Apple engine reads.
    var voiceIdentifier: String?
    /// A Kokoro voice id (e.g. "am_michael"), used when Kokoro reads.
    var kokoroVoiceID: String?
    var pitch: Double = 1.0
    var pace: Double = 1.0
    var readByMe: Bool = false

    static let narratorID = "__narrator__"

    var isNarrator: Bool { id == Self.narratorID }
}

/// Everyone who speaks in a document.
struct Cast: Codable, Hashable {
    var members: [CastMember] = []

    func member(for speaker: String?) -> CastMember? {
        guard let speaker else { return members.first { $0.isNarrator } }
        return members.first { $0.id == speaker }
    }

    mutating func update(_ member: CastMember) {
        if let i = members.firstIndex(where: { $0.id == member.id }) {
            members[i] = member
        } else {
            members.append(member)
        }
    }

    /// Kokoro voices in the order they are handed to characters: alternating
    /// sex and accent, so the first few characters sound as different as
    /// possible from one another.
    static let kokoroCastingOrder = ["am_michael", "bf_emma", "af_bella", "bm_george", "af_sky", "am_adam", "bf_isabella", "am_puck", "af_nicole", "bm_lewis", "af_sarah", "af_heart"]

    /// Builds a cast for `speakers`, in order of first appearance.
    /// - `appleVoices`: Apple voice identifiers to spread across the characters, best first.
    /// - `narratorApple` / `narratorKokoro`: the reader's own voices, kept for narration.
    /// Members that share a voice get a pitch and pace offset so they still sound different.
    static func auto(speakers: [String], appleVoices: [String], narratorApple: String?, narratorKokoro: String) -> Cast {
        var members: [CastMember] = [CastMember(id: CastMember.narratorID, name: "Narrator", voiceIdentifier: narratorApple, kokoroVoiceID: narratorKokoro)]
        let applePool: [String] = {
            let others = appleVoices.filter { $0 != narratorApple }
            return others.isEmpty ? appleVoices : others
        }()
        let kokoroPool = kokoroCastingOrder.filter { $0 != narratorKokoro }
        for (i, speaker) in speakers.enumerated() {
            let apple = applePool.isEmpty ? nil : applePool[i % applePool.count]
            let kokoro = kokoroPool[i % kokoroPool.count]
            let round = applePool.isEmpty ? i : i / applePool.count
            let pitch = [1.0, 0.92, 1.08, 0.86][round % 4]
            let pace = [1.0, 1.04, 0.96, 1.08][round % 4]
            members.append(CastMember(id: speaker, name: Self.displayName(speaker), voiceIdentifier: apple, kokoroVoiceID: kokoro, pitch: pitch, pace: pace))
        }
        return Cast(members: members)
    }

    /// "SOCRATES" becomes "Socrates"; "Phaedr." stays "Phaedr."
    static func displayName(_ label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        if trimmed == trimmed.uppercased(), trimmed.count > 2 {
            return trimmed.lowercased().capitalized
        }
        return trimmed
    }
}

extension Array where Element == Turn {
    /// The turn containing span `index`, by binary search.
    func turnIndex(containing index: Int) -> Int? {
        guard !isEmpty else { return nil }
        var low = 0
        var high = count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if self[mid].start <= index { low = mid } else { high = mid - 1 }
        }
        return self[low].start <= index && index < self[low].end ? low : nil
    }
}

extension Document {
    /// Runs the dialogue parser over every chapter. Chapters that are
    /// dialogues get their labels removed from the text and turns attached.
    /// Returns the speakers found, in order of first appearance.
    @discardableResult
    func detectDialogue() -> [String] {
        var speakers: [String] = []
        var updated = chapters
        var changed = false
        for i in updated.indices {
            guard let result = DialogueParser.parse(updated[i].text) else { continue }
            updated[i].text = result.text
            updated[i].turns = result.turns
            changed = true
            for s in result.speakers where !speakers.contains(s) { speakers.append(s) }
        }
        if changed { chapters = updated }
        return speakers
    }

    /// Every speaker across the book, in order of first appearance.
    var speakers: [String] {
        var out: [String] = []
        for chapter in chapters {
            for turn in chapter.turns ?? [] {
                if let s = turn.speaker, !out.contains(s) { out.append(s) }
            }
        }
        return out
    }
}

/// Finds who says what in a chapter of text.
///
/// Recognizes paragraphs that start with a speaker label:
/// `SOCRATES: ...`, `SOCRATES. ...`, `Socrates: ...`, `Soc. ...`, `Phaedr. ...`.
/// A label counts only if it opens three or more paragraphs, and a chapter is a
/// dialogue only if two or more labels survive and they open at least a third of
/// the paragraphs. Everything else is narration.
///
/// Verified on Project Gutenberg's Jowett translations: Phaedrus and Euthyphro
/// parse as two-speaker dialogues with the introduction as narration; the
/// Apology, a monologue, is rejected.
enum DialogueParser {
    struct Result {
        /// The chapter text with the labels removed, so the voice never reads them.
        var text: String
        var turns: [Turn]
        /// Speakers in order of first appearance.
        var speakers: [String]
    }

    private struct Paragraph {
        var label: String?
        var body: String
    }

    static let minimumAppearances = 3
    static let minimumCoverage = 0.33

    /// Returns nil when the text is not a dialogue.
    static func parse(_ text: String) -> Result? {
        let rawParagraphs = paragraphs(of: text)
        guard rawParagraphs.count >= 6 else { return nil }

        var paragraphs: [Paragraph] = rawParagraphs.map { p in
            if let parts = split(p) { return Paragraph(label: parts.0, body: parts.1) }
            return Paragraph(label: nil, body: p)
        }

        var counts: [String: Int] = [:]
        for p in paragraphs { if let l = p.label { counts[l, default: 0] += 1 } }
        let kept = Set(counts.filter { $0.value >= minimumAppearances }.map(\.key))
        guard kept.count >= 2 else { return nil }

        let labeled = paragraphs.filter { $0.label.map(kept.contains) ?? false }.count
        guard Double(labeled) / Double(paragraphs.count) >= minimumCoverage else { return nil }

        // Labels that did not survive go back into their paragraph as plain text.
        for i in paragraphs.indices {
            if let l = paragraphs[i].label, !kept.contains(l) {
                paragraphs[i] = Paragraph(label: nil, body: rawParagraphs[i])
            }
        }

        var turns: [Turn] = []
        var speakers: [String] = []
        var cursor = 0
        var pieces: [String] = []
        for p in paragraphs {
            let words = TimedText.tokenize(p.body + "\n\n").spans.count
            if words == 0 { continue }
            if let l = p.label, !speakers.contains(l) { speakers.append(l) }
            // Merge with the previous turn when the same speaker continues.
            if let last = turns.last, last.speaker == p.label, last.end == cursor {
                turns[turns.count - 1].end = cursor + words
            } else {
                turns.append(Turn(speaker: p.label, start: cursor, end: cursor + words))
            }
            pieces.append(p.body)
            cursor += words
        }
        guard !turns.isEmpty else { return nil }
        return Result(text: pieces.joined(separator: "\n\n"), turns: turns, speakers: speakers)
    }

    /// Paragraphs are separated by blank lines. Lines inside a paragraph are
    /// unwrapped, which is what Gutenberg text files and PDFs need.
    static func paragraphs(of text: String) -> [String] {
        var result: [String] = []
        var current: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !current.isEmpty {
                    result.append(current.joined(separator: " "))
                    current = []
                }
            } else {
                current.append(trimmed)
            }
        }
        if !current.isEmpty { result.append(current.joined(separator: " ")) }
        return result
    }

    // MARK: Label forms

    private static let allCaps = try! NSRegularExpression(pattern: #"^([A-Z][A-Z'’\-]{1,24}(?: [A-Z][A-Z'’\-]{1,24})?)\s*[:.]\s+(?=\S)"#)
    private static let titleCase = try! NSRegularExpression(pattern: #"^([A-Z][a-z'’\-]{1,24}(?: [A-Z][a-z'’\-]{1,24})?)\s*:\s+(?=\S)"#)
    private static let abbreviation = try! NSRegularExpression(pattern: #"^([A-Z][a-z]{1,7}\.)\s+(?=[A-Z"“])"#)
    private static let ignoredAbbreviations: Set<String> = ["Mr.", "Mrs.", "Ms.", "Dr.", "St.", "Mt.", "No.", "Vol.", "Ch.", "Fig.", "Op.", "Cf."]

    private static func split(_ paragraph: String) -> (String, String)? {
        let ns = paragraph as NSString
        let whole = NSRange(location: 0, length: ns.length)
        for (regex, isAbbreviation) in [(allCaps, false), (titleCase, false), (abbreviation, true)] {
            guard let m = regex.firstMatch(in: paragraph, range: whole), m.numberOfRanges > 1 else { continue }
            let label = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            if isAbbreviation && ignoredAbbreviations.contains(label) { continue }
            let body = ns.substring(from: m.range.location + m.range.length).trimmingCharacters(in: .whitespaces)
            if body.isEmpty { continue }
            return (label, body)
        }
        return nil
    }
}
