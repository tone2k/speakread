import Foundation
import AVFoundation
import UniformTypeIdentifiers

/// Turns a file the user picked into a Document: EPUB and PDF become books,
/// audio files become recordings with a transcript.
enum Importer {
    enum ImportError: LocalizedError {
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .unsupported(let ext): return "Verso cannot open .\(ext) files yet. Try an EPUB, a PDF, or an audio file."
            }
        }
    }

    static let readableTypes: [UTType] = [.epub, .pdf, .plainText, .text, .audio, .mpeg4Audio, .mp3, .wav, .aiff]

    static func importFile(at url: URL, ears: Ears) async throws -> Document {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        if type.conforms(to: .epub) {
            return book(try EPUBImporter.importBook(at: url))
        }
        if type.conforms(to: .pdf) {
            return book(try PDFImporter.importBook(at: url))
        }
        if type.conforms(to: .plainText) || type.conforms(to: .text) || url.pathExtension.lowercased() == "txt" {
            return book(try TextImporter.importBook(at: url))
        }
        if type.conforms(to: .audio) {
            return try await importAudio(at: url, ears: ears)
        }
        throw ImportError.unsupported(url.pathExtension)
    }

    /// Every book gets a dialogue pass: chapters with speaker labels become turns.
    private static func book(_ document: Document) -> Document {
        document.detectDialogue()
        return document
    }

    private static func importAudio(at url: URL, ears: Ears) async throws -> Document {
        // Copy into the library first so playback never depends on the picked location.
        let name = UUID().uuidString + "." + (url.pathExtension.isEmpty ? "m4a" : url.pathExtension)
        let destination = AudioStore.url(for: name)
        try FileManager.default.copyItem(at: url, to: destination)

        let document = Document(kind: .recording, title: url.deletingPathExtension().lastPathComponent)
        document.audioFileName = name
        if let file = try? AVAudioFile(forReading: destination) {
            document.duration = Double(file.length) / file.processingFormat.sampleRate
        }
        document.transcript = try await ears.transcribe(file: destination)
        return document
    }
}
