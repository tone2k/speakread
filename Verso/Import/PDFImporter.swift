import Foundation
import PDFKit

/// Reads a PDF into chapters of plain text, eight pages per chapter.
enum PDFImporter {
    enum PDFError: LocalizedError {
        case cannotOpen
        case noText

        var errorDescription: String? {
            switch self {
            case .cannotOpen: return "This PDF could not be opened."
            case .noText: return "This PDF has no text to read. It may be a scan."
            }
        }
    }

    static func importBook(at url: URL) throws -> Document {
        guard let pdf = PDFDocument(url: url) else { throw PDFError.cannotOpen }
        let pagesPerChapter = 8
        var chapters: [Chapter] = []
        var buffer = ""
        var firstPage = 1
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index), let text = page.string else { continue }
            buffer += text.collapsingWhitespace(keepNewlines: true) + "\n\n"
            let isLast = index == pdf.pageCount - 1
            if (index + 1) % pagesPerChapter == 0 || isLast {
                let body = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty {
                    let lastPage = index + 1
                    let title = firstPage == lastPage ? "Page \(firstPage)" : "Pages \(firstPage)–\(lastPage)"
                    chapters.append(Chapter(title: title, text: body))
                }
                buffer = ""
                firstPage = index + 2
            }
        }
        guard !chapters.isEmpty else { throw PDFError.noText }
        let attributes = pdf.documentAttributes ?? [:]
        let title = (attributes[PDFDocumentAttribute.titleAttribute] as? String)?.collapsingWhitespace()
        let author = (attributes[PDFDocumentAttribute.authorAttribute] as? String)?.collapsingWhitespace() ?? ""
        let document = Document(kind: .book, title: (title?.isEmpty == false ? title! : url.deletingPathExtension().lastPathComponent), author: author)
        document.chapters = chapters
        return document
    }
}
