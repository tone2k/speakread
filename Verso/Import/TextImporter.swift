import Foundation

/// Reads a plain text file into chapters. Project Gutenberg files get their
/// boilerplate stripped, and lines in capitals on their own become chapter breaks.
enum TextImporter {
    enum TextError: LocalizedError {
        case empty

        var errorDescription: String? { "This text file is empty." }
    }

    static func importBook(at url: URL) throws -> Document {
        let data = try Data(contentsOf: url)
        var text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(decoding: data, as: UTF8.self)
        text = text.replacingOccurrences(of: "\r\n", with: "\n")

        var title = url.deletingPathExtension().lastPathComponent
        var author = ""
        if let t = metadata("Title", in: text) { title = t }
        if let a = metadata("Author", in: text) { author = a }
        text = stripGutenberg(text)

        let chapters = split(text)
        guard !chapters.isEmpty else { throw TextError.empty }
        let document = Document(kind: .book, title: title, author: author)
        document.chapters = chapters
        return document
    }

    /// "Title: Phaedrus" lines in a Gutenberg header.
    private static func metadata(_ key: String, in text: String) -> String? {
        for line in text.prefix(4000).components(separatedBy: "\n") where line.hasPrefix(key + ":") {
            let value = line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// Keeps only what lies between the Gutenberg START and END markers, when present.
    private static func stripGutenberg(_ text: String) -> String {
        var body = text
        if let start = body.range(of: "*** START OF"), let lineEnd = body[start.upperBound...].firstIndex(of: "\n") {
            body = String(body[body.index(after: lineEnd)...])
        }
        if let end = body.range(of: "*** END OF") {
            body = String(body[..<end.lowerBound])
        }
        return body
    }

    /// Splits on headings: a short paragraph in capitals with no sentence
    /// punctuation, such as "INTRODUCTION." or "PHAEDRUS". Everything before
    /// the first heading becomes a chapter of its own when it has real text.
    private static func split(_ text: String) -> [Chapter] {
        let paragraphs = DialogueParser.paragraphs(of: text)
        var chapters: [Chapter] = []
        var currentTitle = "Chapter 1"
        var buffer: [String] = []

        func flush() {
            let body = buffer.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if body.split(whereSeparator: { $0.isWhitespace }).count >= 40 {
                chapters.append(Chapter(title: currentTitle, text: body))
            }
            buffer = []
        }

        for p in paragraphs {
            if isHeading(p) {
                flush()
                currentTitle = Cast.displayName(p.trimmingCharacters(in: CharacterSet(charactersIn: ". ")))
            } else {
                buffer.append(p)
            }
        }
        flush()
        if chapters.isEmpty {
            let body = paragraphs.joined(separator: "\n\n")
            if !body.isEmpty { chapters.append(Chapter(title: "Chapter 1", text: body)) }
        }
        return chapters
    }

    private static func isHeading(_ p: String) -> Bool {
        let words = p.split(separator: " ")
        guard (1...6).contains(words.count), p.count <= 48 else { return false }
        guard p == p.uppercased(), p.rangeOfCharacter(from: .letters) != nil else { return false }
        let stripped = p.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return !stripped.contains(":") && !stripped.contains("?") && !stripped.contains("!") && !stripped.contains(",")
    }
}
