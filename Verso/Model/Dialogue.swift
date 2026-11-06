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
    var voiceIdentifier: String?
    var pitch: Double = 1.0
    var pace: Double = 1.0
    var readByMe: Bool = false

    static let narratorID = "__narrator__"

    static func narrator() -> CastMember {
        CastMember(id: narratorID, name: "Narrator")
    }
}

/// Everyone who speaks in a document.
struct Cast: Codable, Hashable {
    var members: [CastMember] = []

    func member(for speaker: String?) -> CastMember? {
        guard let speaker else { return members.first { $0.id == CastMember.narratorID } }
        return members.first { $0.id == speaker }
    }

    /// Builds a cast for `speakers`, in order of first appearance, spreading
    /// `voiceIdentifiers` across them. Members that share a voice get a pitch
    /// and pace offset so they still sound different.
    static func auto(speakers: [String], voiceIdentifiers: [String], narratorVoice: String?) -> Cast {
        var members: [CastMember] = [CastMember(id: CastMember.narratorID, name: "Narrator", voiceIdentifier: narratorVoice)]
        let pool = voiceIdentifiers.filter { $0 != narratorVoice }.isEmpty ? voiceIdentifiers : voiceIdentifiers.filter { $0 != narratorVoice }
        for (i, speaker) in speakers.enumerated() {
            let voice = pool.isEmpty ? nil : pool[i % pool.count]
            let round = pool.isEmpty ? i : i / pool.count
            let pitch = [1.0, 0.92, 1.08, 0.86][round % 4]
            let pace = [1.0, 1.04, 0.96, 1.08][round % 4]
            members.append(CastMember(id: speaker, name: Self.displayName(speaker), voiceIdentifier: voice, pitch: pitch, pace: pace))
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

/// Finds who says what in a chapter of text.
///
/// Recognizes paragraphs that start with a speaker label:
/// `SOCRATES: ...`, `SOCRATES. ...`, `Socrates: ...`, `Soc. ...`, `Phaedr. ...`.
/// A label counts only if it opens three or more paragraphs, and a chapter is a
/// dialogue only if two or more labels survive and they open at least a third of
/// the paragraphs. Everything else is narration.
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
