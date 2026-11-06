import Foundation

/// One word (or punctuation group) with the time it is spoken.
/// Transcripts produce this from audio. Books produce audio from this.
struct TimedSpan: Codable, Hashable, Identifiable {
    var id: Int
    var text: String
    var start: TimeInterval
    var end: TimeInterval
    var confidence: Float = 1
    var isFinal: Bool = true
}

/// Text with a time on every word. The shared model for both sides of Verso.
struct TimedText: Codable, Hashable {
    var spans: [TimedSpan] = []

    var plain: String { spans.map(\.text).joined() }
    var isEmpty: Bool { spans.isEmpty }
    var duration: TimeInterval { spans.last?.end ?? 0 }

    init(spans: [TimedSpan] = []) {
        self.spans = spans
    }

    /// Index of the span spoken at `time`, or the last one before it.
    func index(at time: TimeInterval) -> Int? {
        guard !spans.isEmpty else { return nil }
        var low = 0
        var high = spans.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if spans[mid].start <= time { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// Splits plain text into word spans, keeping each word's trailing whitespace
    /// so `plain` rebuilds the original. Times are filled in later by the reader.
    static func tokenize(_ text: String) -> TimedText {
        var spans: [TimedSpan] = []
        var current = ""
        var inSpace = false
        func flush() {
            if !current.isEmpty {
                spans.append(TimedSpan(id: spans.count, text: current, start: 0, end: 0))
                current = ""
            }
        }
        for ch in text {
            let space = ch.isWhitespace
            if inSpace && !space { flush() }
            current.append(ch)
            inSpace = space
        }
        flush()
        return TimedText(spans: spans)
    }

    /// Re-numbers ids after concatenation.
    func renumbered() -> TimedText {
        var out = self
        for i in out.spans.indices { out.spans[i].id = i }
        return out
    }

    /// Character offset where each span starts in `plain`.
    func characterOffsets() -> [Int] {
        var offsets: [Int] = []
        offsets.reserveCapacity(spans.count)
        var total = 0
        for span in spans {
            offsets.append(total)
            total += span.text.utf16.count
        }
        return offsets
    }

    /// The span that contains character offset `offset` (UTF-16, as NSRange counts).
    static func spanIndex(forOffset offset: Int, offsets: [Int]) -> Int? {
        guard !offsets.isEmpty else { return nil }
        var low = 0
        var high = offsets.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if offsets[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// Spans whose text ends a sentence.
    func sentenceEnds() -> [Int] {
        spans.indices.filter { i in
            let t = spans[i].text.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.hasSuffix(".") || t.hasSuffix("?") || t.hasSuffix("!") || t.hasSuffix(".”") || t.hasSuffix(".\"")
        }
    }
}

/// A chapter mark inside a recording.
struct Mark: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var time: TimeInterval
    var label: String
}

/// A chapter of a book: a title and its text. A dialogue chapter also knows
/// who says each span, as turns.
struct Chapter: Codable, Hashable {
    var title: String
    var text: String
    var turns: [Turn]? = nil

    var isDialogue: Bool { !(turns?.isEmpty ?? true) }
}

func formatTimecode(_ seconds: TimeInterval, tenths: Bool = false) -> String {
    let s = max(0, seconds)
    let h = Int(s) / 3600
    let m = (Int(s) % 3600) / 60
    let sec = Int(s) % 60
    let base = h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    if tenths {
        let t = Int((s - floor(s)) * 10)
        return base + ".\(t)"
    }
    return base
}

func formatMinutesLeft(_ seconds: TimeInterval) -> String {
    let m = Int(ceil(max(0, seconds) / 60))
    if m < 1 { return "less than a minute left" }
    if m == 1 { return "1 min left" }
    return "\(m) min left"
}
