import Foundation

/// Reads an EPUB into chapters of plain text, in spine order.
enum EPUBImporter {
    enum EPUBError: LocalizedError {
        case noContainer
        case noPackage

        var errorDescription: String? {
            switch self {
            case .noContainer: return "This EPUB has no container.xml."
            case .noPackage: return "This EPUB has no package file."
            }
        }
    }

    static func importBook(at url: URL) throws -> Document {
        let zip = try ZipReader(url: url)

        // 1. container.xml names the package (.opf) file.
        guard let containerData = try? zip.contents(of: "META-INF/container.xml") else { throw EPUBError.noContainer }
        let container = XMLScan(data: containerData)
        guard let opfPath = container.firstAttribute("full-path", onElement: "rootfile") else { throw EPUBError.noPackage }

        // 2. The package lists the manifest and the reading order (spine).
        let opfData = try zip.contents(of: opfPath)
        let opf = XMLScan(data: opfData)
        let opfDirectory = (opfPath as NSString).deletingLastPathComponent

        var hrefByID: [String: String] = [:]
        for item in opf.elements(named: "item") {
            if let id = item.attributes["id"], let href = item.attributes["href"] { hrefByID[id] = href }
        }
        let spine = opf.elements(named: "itemref").compactMap { $0.attributes["idref"] }
        let title = opf.text(ofElement: "title") ?? url.deletingPathExtension().lastPathComponent
        let author = opf.text(ofElement: "creator") ?? ""

        // 3. Each spine item becomes a chapter.
        var chapters: [Chapter] = []
        for idref in spine {
            guard let href = hrefByID[idref] else { continue }
            let path = opfDirectory.isEmpty ? href : opfDirectory + "/" + href
            let decoded = path.removingPercentEncoding ?? path
            guard let xhtml = try? zip.contents(of: decoded) else { continue }
            let extracted = HTMLText.extract(from: xhtml)
            let body = extracted.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if body.count < 40 { continue }
            let chapterTitle = extracted.heading ?? "Chapter \(chapters.count + 1)"
            chapters.append(Chapter(title: chapterTitle, text: body))
        }

        let document = Document(kind: .book, title: title, author: author)
        document.chapters = chapters
        return document
    }
}

/// Extracts readable text from XHTML. Headings, paragraphs and breaks become new lines.
enum HTMLText {
    struct Result {
        var text: String
        var heading: String?
    }

    /// HTML entities that XML does not know. They would stop the parser.
    private static let entities: [String: String] = [
        "&nbsp;": "&#160;", "&mdash;": "&#8212;", "&ndash;": "&#8211;", "&hellip;": "&#8230;",
        "&lsquo;": "&#8216;", "&rsquo;": "&#8217;", "&ldquo;": "&#8220;", "&rdquo;": "&#8221;",
        "&copy;": "&#169;", "&shy;": "", "&emsp;": "&#8195;", "&ensp;": "&#8194;", "&thinsp;": "&#8201;",
        "&eacute;": "&#233;", "&egrave;": "&#232;", "&agrave;": "&#224;", "&ccedil;": "&#231;",
        "&ouml;": "&#246;", "&uuml;": "&#252;", "&auml;": "&#228;", "&szlig;": "&#223;", "&ntilde;": "&#241;"
    ]

    static func extract(from data: Data) -> Result {
        var data = data
        if var text = String(data: data, encoding: .utf8), text.contains("&") {
            for (entity, replacement) in entities where text.contains(entity) {
                text = text.replacingOccurrences(of: entity, with: replacement)
            }
            data = Data(text.utf8)
        }
        let parser = TextParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.shouldResolveExternalEntities = false
        xml.parse()
        if parser.text.trimmingCharacters(in: .whitespaces).isEmpty, let raw = String(data: data, encoding: .utf8) {
            // Fall back to a rough strip if the XHTML was not well formed.
            let stripped = raw.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            return Result(text: stripped.collapsingWhitespace(), heading: nil)
        }
        return Result(text: parser.text.collapsingWhitespace(keepNewlines: true), heading: parser.heading)
    }

    private final class TextParser: NSObject, XMLParserDelegate {
        var text = ""
        var heading: String?
        private var inBody = false
        private var inHeading = false
        private var headingBuffer = ""
        private var skipDepth = 0
        private let blocks: Set<String> = ["p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "li", "br", "blockquote", "section", "article", "tr", "dd", "dt", "figcaption"]

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            let tag = name.lowercased()
            if tag == "body" { inBody = true }
            if ["script", "style", "head", "title"].contains(tag) { skipDepth += 1 }
            if blocks.contains(tag) { text += "\n" }
            if tag.hasPrefix("h"), tag.count == 2, heading == nil { inHeading = true; headingBuffer = "" }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let tag = name.lowercased()
            if ["script", "style", "head", "title"].contains(tag) { skipDepth = max(0, skipDepth - 1) }
            if blocks.contains(tag) { text += "\n" }
            if inHeading, tag.hasPrefix("h"), tag.count == 2 {
                inHeading = false
                let h = headingBuffer.collapsingWhitespace()
                if !h.isEmpty { heading = h }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard skipDepth == 0 else { return }
            text += string
            if inHeading { headingBuffer += string }
        }
    }
}

/// A tiny forgiving XML scanner for container.xml and the OPF package.
struct XMLScan {
    struct Element {
        let name: String
        let attributes: [String: String]
        let text: String
    }

    private let elements: [Element]

    init(data: Data) {
        let collector = Collector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.parse()
        elements = collector.elements
    }

    func elements(named name: String) -> [Element] {
        elements.filter { $0.name.lowercased() == name.lowercased() }
    }

    func firstAttribute(_ attribute: String, onElement name: String) -> String? {
        elements(named: name).first?.attributes[attribute]
    }

    func text(ofElement name: String) -> String? {
        let t = elements(named: name).first?.text.collapsingWhitespace()
        return (t?.isEmpty ?? true) ? nil : t
    }

    private final class Collector: NSObject, XMLParserDelegate {
        var elements: [Element] = []
        private var stack: [(String, [String: String], String)] = []

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            stack.append((name, attributes, ""))
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard !stack.isEmpty else { return }
            stack[stack.count - 1].2 += string
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            guard let top = stack.popLast() else { return }
            elements.append(Element(name: top.0, attributes: top.1, text: top.2))
        }
    }
}

extension String {
    func collapsingWhitespace(keepNewlines: Bool = false) -> String {
        if keepNewlines {
            let lines = components(separatedBy: .newlines)
                .map { $0.replacingOccurrences(of: "[ \\t\\r\\u{00A0}]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            var out: [String] = []
            for line in lines {
                if line.isEmpty {
                    if out.last != "" { out.append("") }
                } else {
                    out.append(line)
                }
            }
            return out.joined(separator: "\n").replacingOccurrences(of: "\n\n+", with: "\n\n", options: .regularExpression)
        }
        return replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
