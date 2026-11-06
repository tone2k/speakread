import Foundation
import SwiftData

/// A recording (something you said) or a book (something you read).
@Model
final class Document {
    enum Kind: String, Codable {
        case recording
        case book
    }

    @Attribute(.unique) var id: UUID
    var title: String
    var author: String
    var kindRaw: String
    var createdAt: Date
    var duration: TimeInterval
    var audioFileName: String?
    var transcriptData: Data?
    var chaptersData: Data?
    var marksData: Data?
    var castData: Data?
    var chapterIndex: Int
    var spanIndex: Int
    var wordCount: Int
    /// One-sentence summary for list rows; generated on-device, lazily when missing.
    var summary: String?
    /// What kind of recording this is (`RecordingKind.rawValue`), once judged.
    var kindLabel: String?
    /// A meeting's digest, as JSON. Nil until one is made.
    var digestData: Data?

    @Relationship(deleteRule: .cascade, inverse: \Note.document)
    var notes: [Note] = []

    // Decoded-blob caches live in a plain, non-observed box (P22): the old
    // @Transient cache properties were WRITTEN by getters during view
    // reads (observation churn mid-render) and validated by comparing
    // whole multi-MB blobs. The box trusts the setters — every mutation
    // in the app goes through them — and decodes at most once per change.
    @Transient private var cacheBox = DocumentCacheBox()

    private final class DocumentCacheBox {
        var transcript: TimedText?
        var chapters: [Chapter]?
        var marks: [Mark]?
        /// Span-count prefix sums over the chapters: starts[i] is the span
        /// index chapter i begins at; the last element is the total (P3).
        var chapterSpanStarts: [Int]?
        var foldedSearchText: String?
    }

    init(kind: Kind, title: String, author: String = "", createdAt: Date = .now) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
        self.duration = 0
        self.chapterIndex = 0
        self.spanIndex = 0
        self.wordCount = 0
    }

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .recording }
        set { kindRaw = newValue.rawValue }
    }

    var transcript: TimedText {
        get {
            if let cached = cacheBox.transcript { return cached }
            let value = transcriptData.flatMap { try? JSONDecoder().decode(TimedText.self, from: $0) } ?? TimedText()
            cacheBox.transcript = value
            return value
        }
        set {
            transcriptData = try? JSONEncoder().encode(newValue)
            wordCount = newValue.spans.count
            cacheBox.transcript = newValue
            cacheBox.foldedSearchText = nil
        }
    }

    var chapters: [Chapter] {
        get {
            if let cached = cacheBox.chapters { return cached }
            let value = chaptersData.flatMap { try? JSONDecoder().decode([Chapter].self, from: $0) } ?? []
            cacheBox.chapters = value
            return value
        }
        set {
            chaptersData = try? JSONEncoder().encode(newValue)
            wordCount = newValue.reduce(0) { $0 + $1.text.split(whereSeparator: { $0.isWhitespace }).count }
            cacheBox.chapters = newValue
            cacheBox.chapterSpanStarts = nil
            cacheBox.foldedSearchText = nil
        }
    }

    var marks: [Mark] {
        get {
            if let cached = cacheBox.marks { return cached }
            let value = marksData.flatMap { try? JSONDecoder().decode([Mark].self, from: $0) } ?? []
            cacheBox.marks = value
            return value
        }
        set {
            marksData = try? JSONEncoder().encode(newValue)
            cacheBox.marks = newValue
        }
    }

    /// Span-count prefix sums over the chapters (P3): `chapterSpanStarts[i]`
    /// is the global span index chapter i starts at, and the last element
    /// is the book's total span count. Built once per chapters change —
    /// tokenizing exactly as the Reader does, so the counts agree — and
    /// cached in the box; progress is O(1) after that.
    var chapterSpanStarts: [Int] {
        if let cached = cacheBox.chapterSpanStarts { return cached }
        var starts: [Int] = []
        var total = 0
        for chapter in chapters {
            starts.append(total)
            total += TimedText.tokenize(chapter.text).spans.count
        }
        starts.append(total)
        cacheBox.chapterSpanStarts = starts
        return starts
    }

    /// Title + author + full text, folded once for search (P17).
    var foldedSearchText: String {
        if let cached = cacheBox.foldedSearchText { return cached }
        let raw: String
        switch kind {
        case .recording:
            raw = title + "\n" + author + "\n" + transcript.plain
        case .book:
            raw = title + "\n" + author + "\n" + chapters.map(\.text).joined(separator: "\n")
        }
        let folded = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
        cacheBox.foldedSearchText = folded
        return folded
    }

    /// The characters of a dialogue and their voices. Nil for ordinary books.
    var cast: Cast? {
        get { castData.flatMap { try? JSONDecoder().decode(Cast.self, from: $0) } }
        set { castData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var isDialogue: Bool { chapters.contains { $0.isDialogue } }

    var digest: MeetingDigest? {
        get { digestData.flatMap { try? JSONDecoder().decode(MeetingDigest.self, from: $0) } }
        set { digestData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var recordingKind: RecordingKind? {
        kindLabel.flatMap(RecordingKind.init(rawValue:))
    }

    var isMeeting: Bool { recordingKind == .meeting }

    /// 0...1 through the whole document.
    var progress: Double {
        switch kind {
        case .recording:
            guard duration > 0, let last = transcript.spans.indices.last, last > 0 else { return 0 }
            return min(1, Double(spanIndex) / Double(last))
        case .book:
            let starts = chapterSpanStarts
            guard starts.count > 1 else { return 0 }
            let total = starts[starts.count - 1]
            guard total > 0 else { return 0 }
            let chapter = min(max(chapterIndex, 0), starts.count - 2)
            return min(1, Double(starts[chapter] + spanIndex) / Double(total))
        }
    }

    /// Rough time left at a normal reading pace (2.6 words per second).
    var estimatedSecondsLeft: TimeInterval {
        Double(wordCount) * (1 - progress) / 2.6
    }

    var firstLine: String {
        switch kind {
        case .recording:
            return String(transcript.plain.prefix(140))
        case .book:
            return String(chapters.first?.text.prefix(140) ?? "")
        }
    }
}

/// A spoken note pinned to a sentence of a book.
@Model
final class Note {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var chapterIndex: Int
    var spanIndex: Int
    var text: String
    var audioFileName: String?
    var document: Document?

    init(chapterIndex: Int, spanIndex: Int, text: String, audioFileName: String?) {
        self.id = UUID()
        self.createdAt = .now
        self.chapterIndex = chapterIndex
        self.spanIndex = spanIndex
        self.text = text
        self.audioFileName = audioFileName
    }
}

/// Where recordings live on disk.
enum AudioStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Audio", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func url(for name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
    }
}
