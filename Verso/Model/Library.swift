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
    var chapterIndex: Int
    var spanIndex: Int
    var wordCount: Int

    @Relationship(deleteRule: .cascade, inverse: \Note.document)
    var notes: [Note] = []

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
        get { transcriptData.flatMap { try? JSONDecoder().decode(TimedText.self, from: $0) } ?? TimedText() }
        set {
            transcriptData = try? JSONEncoder().encode(newValue)
            wordCount = newValue.spans.count
        }
    }

    var chapters: [Chapter] {
        get { chaptersData.flatMap { try? JSONDecoder().decode([Chapter].self, from: $0) } ?? [] }
        set {
            chaptersData = try? JSONEncoder().encode(newValue)
            wordCount = newValue.reduce(0) { $0 + $1.text.split(whereSeparator: { $0.isWhitespace }).count }
        }
    }

    var marks: [Mark] {
        get { marksData.flatMap { try? JSONDecoder().decode([Mark].self, from: $0) } ?? [] }
        set { marksData = try? JSONEncoder().encode(newValue) }
    }

    /// 0...1 through the whole document.
    var progress: Double {
        switch kind {
        case .recording:
            guard duration > 0, let last = transcript.spans.indices.last, last > 0 else { return 0 }
            return min(1, Double(spanIndex) / Double(last))
        case .book:
            let chapters = self.chapters
            guard !chapters.isEmpty, wordCount > 0 else { return 0 }
            let before = chapters.prefix(chapterIndex).reduce(0) { $0 + $1.text.split(whereSeparator: { $0.isWhitespace }).count }
            return min(1, Double(before + spanIndex) / Double(wordCount))
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
