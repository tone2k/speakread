import Foundation
import SwiftData
import Observation
import AVFoundation

/// The one object the screens talk to. It owns the recorder, the reader, the player
/// and the user's settings, and it knows what is "in progress" so the ribbon can show it.
@MainActor
@Observable
final class Engine {
    static let shared = Engine()

    enum Route: Hashable {
        case recording
        case reading(UUID)
        case playback(UUID)
        case settings
    }

    /// What the ribbon tab on the closed phone points at.
    enum Activity: Equatable {
        case none
        case recording
        case reading(UUID)
        case playing(UUID)
    }

    let recorder = Recorder()
    let reader = Reader()
    let player = Player()
    let settings = Settings()

    var path: [Route] = []
    var activity: Activity = .none
    var lastError: String?
    var isImporting = false

    private(set) var context: ModelContext?

    func attach(context: ModelContext) {
        self.context = context
        reader.onProgress = { [weak self] document, chapter, span in
            document.chapterIndex = chapter
            document.spanIndex = span
            try? self?.context?.save()
        }
        seedSampleIfNeeded()
    }

    /// Puts one public-domain book on the shelf the first time Verso opens.
    private func seedSampleIfNeeded() {
        guard let context, !UserDefaults.standard.bool(forKey: SampleBook.seededKey) else { return }
        context.insert(SampleBook.make())
        try? context.save()
        UserDefaults.standard.set(true, forKey: SampleBook.seededKey)
    }

    // MARK: Recording

    /// Starts a recording and shows the recording screen. Called from the UI and from Siri.
    func startRecording() {
        guard !recorder.isRecording else {
            if path.last != .recording { path.append(.recording) }
            return
        }
        if reader.isSpeaking { reader.pause() }
        player.pause()
        Task {
            do {
                try await recorder.start(ears: settings.makeEars(), title: Self.defaultRecordingTitle())
                activity = .recording
                if path.last != .recording { path.append(.recording) }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func stopRecording() async {
        guard let context else { return }
        let document = await recorder.stop()
        if let document {
            context.insert(document)
            try? context.save()
        }
        activity = .none
        if path.last == .recording { path.removeLast() }
    }

    static func defaultRecordingTitle() -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE HH:mm"
        return f.string(from: .now)
    }

    // MARK: Reading

    func open(_ document: Document) {
        switch document.kind {
        case .book:
            reader.load(document)
            path.append(.reading(document.id))
        case .recording:
            player.load(document)
            path.append(.playback(document.id))
        }
    }

    func playReading(_ document: Document) {
        if reader.document?.id != document.id { reader.load(document) }
        reader.play()
        activity = .reading(document.id)
    }

    func document(id: UUID) -> Document? {
        guard let context else { return nil }
        let descriptor = FetchDescriptor<Document>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    /// The document the ribbon tab should continue, if any.
    var continuing: Document? {
        switch activity {
        case .reading(let id), .playing(let id): return document(id: id)
        case .recording, .none: return reader.document ?? player.document
        }
    }

    // MARK: Margin notes

    /// Records a short note while a book is open and pins it to the sentence being read.
    func beginMarginNote() {
        guard !recorder.isRecording else { return }
        let wasSpeaking = reader.isSpeaking && !reader.isPaused
        if wasSpeaking { reader.pause() }
        Task {
            do {
                try await recorder.start(ears: settings.makeEars(), title: "Note")
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func endMarginNote() {
        guard recorder.isRecording, let book = reader.document, let context else { return }
        let chapter = reader.chapterIndex
        let span = reader.currentIndex ?? book.spanIndex
        Task {
            guard let recorded = await recorder.stop() else { return }
            let note = Note(chapterIndex: chapter, spanIndex: span, text: recorded.transcript.plain, audioFileName: recorded.audioFileName)
            note.document = book
            book.notes.append(note)
            try? context.save()
            if reader.isPaused { reader.resume() }
        }
    }

    // MARK: Import

    func importFile(at url: URL) async {
        guard let context else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            let document = try await Importer.importFile(at: url, ears: settings.makeEars())
            context.insert(document)
            try context.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func delete(_ document: Document) {
        guard let context else { return }
        if reader.document?.id == document.id { reader.stop() }
        if player.document?.id == document.id { player.stop() }
        if let name = document.audioFileName { AudioStore.remove(name) }
        context.delete(document)
        try? context.save()
    }
}

/// User settings, kept in UserDefaults.
@MainActor
@Observable
final class Settings {
    enum EarsChoice: String, CaseIterable, Identifiable {
        case apple
        case classic

        var id: String { rawValue }
        var title: String {
            switch self {
            case .apple: return "Apple on-device"
            case .classic: return "Apple dictation"
            }
        }
        var subtitle: String {
            switch self {
            case .apple: return "Recommended · runs on this iPhone · word timing"
            case .classic: return "Compatible · falls back to Apple's servers if needed"
            }
        }
    }

    var ears: EarsChoice {
        didSet { UserDefaults.standard.set(ears.rawValue, forKey: "ears") }
    }
    var voiceIdentifier: String? {
        didSet { UserDefaults.standard.set(voiceIdentifier, forKey: "voice") }
    }
    var rateMultiplier: Double {
        didSet { UserDefaults.standard.set(rateMultiplier, forKey: "rate") }
    }
    var sleepMinutes: Int {
        didSet { UserDefaults.standard.set(sleepMinutes, forKey: "sleep") }
    }

    init() {
        let d = UserDefaults.standard
        ears = EarsChoice(rawValue: d.string(forKey: "ears") ?? "") ?? .apple
        voiceIdentifier = d.string(forKey: "voice")
        let rate = d.double(forKey: "rate")
        rateMultiplier = rate == 0 ? 1.0 : rate
        let sleep = d.integer(forKey: "sleep")
        sleepMinutes = sleep == 0 ? 15 : sleep
    }

    func makeEars() -> Ears {
        switch ears {
        case .apple: return AppleEars()
        case .classic: return ClassicEars()
        }
    }

    var voice: AVSpeechSynthesisVoice? {
        if let id = voiceIdentifier, let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        return Reader.bestDefaultVoice()
    }
}
