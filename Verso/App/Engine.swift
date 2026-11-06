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
    /// Lock-screen / Control Center transport + the recording Live
    /// Activity, driven entirely off the three owners above.
    private(set) var transport: TransportCenter?

    var path: [Route] = []
    var activity: Activity = .none {
        didSet { refreshContinuing() }
    }
    var lastError: String?
    var isImporting = false

    private(set) var context: ModelContext?

    /// The document the continue strip points at, kept current by the
    /// flows that change it (P16) — the old computed property ran a
    /// SwiftData fetch inside `PocketView.body` on every render.
    private(set) var continuingDocument: Document?

    func attach(context: ModelContext) {
        self.context = context
        reader.onSavePoint = { [weak self] document, chapter, span in
            // Fires ONLY at save points (pause, stop, chapter change,
            // jumps, backgrounding), so writing and saving immediately is
            // cheap — and the stored position is never stale by more than
            // the current uninterrupted play stretch (P4).
            document.chapterIndex = chapter
            document.spanIndex = span
            try? self?.context?.save()
        }
        syncReaderVoice()
        if transport == nil {
            let center = TransportCenter(engine: self)
            transport = center
            center.start()
        }
        seedSampleIfNeeded()
        #if DEBUG
        Self.writeVoiceRoster()
        #endif
        // Prewarm the Kokoro pipeline shortly after launch when it's the
        // chosen engine, so the first play tap doesn't pay the load (P8).
        if settings.voiceEngine == .kokoro {
            let voice = settings.kokoroVoice
            Task {
                try? await Task.sleep(for: .seconds(2))
                _ = await KokoroVoice.shared.prepareIfDownloaded(voice: voice)
            }
        }
    }

    func refreshContinuing() {
        switch activity {
        case .reading, .playing, .recording, .none:
            let candidate = reader.document ?? player.document
            // Never point the strip at a deleted (or never-inserted)
            // model: a stale candidate must not resurrect on Pocket.
            if let candidate, candidate.isDeleted || candidate.modelContext == nil {
                continuingDocument = nil
            } else {
                continuingDocument = candidate
            }
        }
    }

    /// A small diagnostic in the app's Documents folder: every speech voice
    /// on the device with its quality tier, and the one Verso would pick.
    /// Readable via devicectl; makes "which voices are actually installed"
    /// a fact instead of a guess.
    private static func writeVoiceRoster() {
        Task.detached(priority: .utility) {
            let voices = AVSpeechSynthesisVoice.speechVoices()
            var lines = voices.map { v in
                let quality = v.quality == .premium ? "premium" : v.quality == .enhanced ? "enhanced" : "default"
                return "\(quality)\t\(v.language)\t\(v.name)\t\(v.identifier)"
            }
            lines.sort()
            let pickedID = await MainActor.run { Reader.bestDefaultVoice()?.identifier ?? "none" }
            lines.append("BEST-DEFAULT\t\(pickedID)")
            guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            try? lines.joined(separator: "\n").write(to: dir.appendingPathComponent("voices.txt"), atomically: true, encoding: .utf8)
        }
    }

    /// Puts one public-domain book and one dialogue on the shelf the first time Verso opens.
    private func seedSampleIfNeeded() {
        guard let context else { return }
        if !UserDefaults.standard.bool(forKey: SampleBook.seededKey) {
            context.insert(SampleBook.make())
            UserDefaults.standard.set(true, forKey: SampleBook.seededKey)
        }
        if !UserDefaults.standard.bool(forKey: SampleBook.dialogueSeededKey) {
            let dialogue = SampleBook.makeDialogue()
            dialogue.detectDialogue()
            assignCastIfNeeded(dialogue)
            context.insert(dialogue)
            UserDefaults.standard.set(true, forKey: SampleBook.dialogueSeededKey)
        }
        try? context.save()
    }

    // MARK: Dialogues

    /// Gives a dialogue its cast: one voice per speaker, the reader's own
    /// voices for narration. Books that are not dialogues are left alone.
    func assignCastIfNeeded(_ document: Document) {
        guard document.kind == .book, document.isDialogue, document.cast == nil else { return }
        document.cast = Cast.auto(
            speakers: document.speakers,
            appleVoices: Reader.castableVoices().map(\.identifier),
            narratorApple: settings.voice?.identifier,
            narratorKokoro: settings.kokoroVoice
        )
    }

    /// Saves an edited cast and hands it to the reader if the book is open.
    func updateCast(_ cast: Cast, for document: Document) {
        document.cast = cast
        try? context?.save()
        if reader.document?.id == document.id {
            reader.cast = cast
            if reader.isSpeaking, !reader.isPaused { reader.play(from: reader.currentIndex) }
        }
    }

    // MARK: Voice selection — one active voice for the whole app

    /// Every voice change in the app funnels through these three: picking
    /// ANY voice — Apple stock, the Personal Voice, a Kokoro voice — makes
    /// it the one active selection (see `Settings.voiceSelection`), and the
    /// Reader is re-synced on the spot.
    func selectVoiceEngine(_ choice: Settings.VoiceEngineChoice) {
        guard settings.voiceEngine != choice else { return }
        settings.voiceEngine = choice
        syncReaderVoice()
    }

    func selectAppleVoice(_ voice: AVSpeechSynthesisVoice) {
        settings.voiceIdentifier = voice.identifier
        settings.voiceEngine = .apple
        syncReaderVoice()
    }

    func selectKokoroVoice(_ id: String) {
        settings.kokoroVoice = id
        settings.voiceEngine = .kokoro
        syncReaderVoice()
        Task { await KokoroVoice.shared.preload(voice: id) }
    }

    /// Pushes the persisted selection into the Reader. Mid-playback the
    /// Reader restarts the current sentence in the new voice — position
    /// is never lost (see `Reader.voiceSettingsChanged`).
    func syncReaderVoice() {
        reader.voiceEngine = settings.voiceEngine
        reader.kokoroVoiceID = settings.kokoroVoice
        reader.voice = settings.voice
        reader.voiceSettingsChanged()
    }

    // MARK: Recording

    /// Starts a recording and shows the recording screen. Called from the UI and from Siri.
    func startRecording() {
        guard !recorder.isRecording, !recorder.isFinishing else {
            if path.last != .recording { path.append(.recording) }
            return
        }
        if reader.isSpeaking { reader.pause() }
        player.pause()
        // Optimistic: show the recording screen now. The recorder flips its
        // own state immediately too; setup finishes behind the transition.
        activity = .recording
        if path.last != .recording { path.append(.recording) }
        Task {
            do {
                try await recorder.start(ears: settings.makeEars(), title: Self.defaultRecordingTitle())
            } catch {
                activity = .none
                if path.last == .recording { path.removeLast() }
                lastError = error.localizedDescription
            }
        }
    }

    func stopRecording() async {
        guard let context else { return }
        // Leave the recording screen now; transcription finalizes behind the
        // transition and the document lands on the shelf when it is ready.
        activity = .none
        if path.last == .recording { path.removeLast() }
        let document = await recorder.stop()
        if let document {
            context.insert(document)
            try? context.save()
            Summarizer.generateIfNeeded(for: document)
            MeetingDigester.shared.detectAndDigestIfNeeded(for: document)
        }
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
        refreshContinuing()
    }

    func playReading(_ document: Document) {
        if reader.document?.id != document.id { reader.load(document) }
        reader.play()
        activity = .reading(document.id)
        refreshContinuing()
    }

    func document(id: UUID) -> Document? {
        guard let context else { return nil }
        let descriptor = FetchDescriptor<Document>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    /// The document the continue strip should continue, if any.
    var continuing: Document? { continuingDocument }

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
            assignCastIfNeeded(document)
            context.insert(document)
            try context.save()
            Summarizer.generateIfNeeded(for: document)
            MeetingDigester.shared.detectAndDigestIfNeeded(for: document)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func delete(_ document: Document) {
        guard let context else { return }
        // Unload, not just stop: Reader.stop() keeps its document, and
        // refreshContinuing() would re-point the continue strip at the
        // deleted book — the bug that left deleted books on Pocket.
        if reader.document?.id == document.id { reader.unload() }
        if player.document?.id == document.id { player.stop() }
        if let name = document.audioFileName { AudioStore.remove(name) }
        context.delete(document)
        try? context.save()
        if continuingDocument?.id == document.id { continuingDocument = nil }
        refreshContinuing()
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

    enum VoiceEngineChoice: String, CaseIterable, Identifiable {
        case kokoro
        case apple

        var id: String { rawValue }
        var title: String {
            switch self {
            case .kokoro: return "Kokoro (on-device)"
            case .apple: return "Apple voices"
            }
        }
        var subtitle: String {
            switch self {
            case .kokoro: return "Neural voice · runs on this iPhone · one-time model download"
            case .apple: return "Built-in voices · the safe fallback"
            }
        }
    }

    /// Light / dark / follow-the-phone. Mapped to a SwiftUI
    /// `ColorScheme?` in RootView; HUD tokens resolve per scheme.
    enum AppearanceChoice: String, CaseIterable, Identifiable {
        case system, light, dark

        var id: String { rawValue }
        var title: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
    }

    var appearance: AppearanceChoice {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }
    var ears: EarsChoice {
        didSet { UserDefaults.standard.set(ears.rawValue, forKey: "ears") }
    }
    var voiceIdentifier: String? {
        didSet { UserDefaults.standard.set(voiceIdentifier, forKey: "voice") }
    }
    var voiceEngine: VoiceEngineChoice {
        didSet { UserDefaults.standard.set(voiceEngine.rawValue, forKey: "voiceEngine") }
    }
    var kokoroVoice: String {
        didSet { UserDefaults.standard.set(kokoroVoice, forKey: "kokoroVoice") }
    }
    var rateMultiplier: Double {
        didSet { UserDefaults.standard.set(rateMultiplier, forKey: "rate") }
    }
    var sleepMinutes: Int {
        didSet { UserDefaults.standard.set(sleepMinutes, forKey: "sleep") }
    }

    init() {
        let d = UserDefaults.standard
        appearance = AppearanceChoice(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        ears = EarsChoice(rawValue: d.string(forKey: "ears") ?? "") ?? .apple
        voiceIdentifier = d.string(forKey: "voice")
        voiceEngine = VoiceEngineChoice(rawValue: d.string(forKey: "voiceEngine") ?? "") ?? .apple
        kokoroVoice = d.string(forKey: "kokoroVoice") ?? KokoroVoice.defaultVoiceID
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

    /// The ONE active reading voice. The persisted stores (`voiceEngine`,
    /// `kokoroVoice`, `voiceIdentifier`) are just its memory: the engine
    /// choice decides which store wins — that is also the migration rule
    /// for libraries saved by older builds, so exactly one voice can ever
    /// read as "selected" anywhere in the UI.
    enum VoiceSelection: Equatable {
        case kokoro(String)
        case apple(String)
    }

    var voiceSelection: VoiceSelection {
        switch voiceEngine {
        case .kokoro:
            return .kokoro(kokoroVoice)
        case .apple:
            return .apple(voiceIdentifier ?? Reader.bestDefaultVoice()?.identifier ?? "")
        }
    }

    /// The active voice's display name for readouts (book view, picker).
    /// The Personal Voice is "Your Voice" — its name, everywhere it names
    /// the voice; the literal iOS feature name survives only in the
    /// directions that walk Apple's own Settings menus.
    var activeVoiceDisplayName: String {
        switch voiceSelection {
        case .kokoro(let id):
            return KokoroVoice.englishVoices.first { $0.id == id }?.name ?? "Kokoro"
        case .apple(let id):
            guard let voice = AVSpeechSynthesisVoice(identifier: id) else { return "Default" }
            return voice.voiceTraits.contains(.isPersonalVoice) ? "Your Voice" : voice.name
        }
    }
}
