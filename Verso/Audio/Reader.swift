import Foundation
import AVFoundation
import Observation

/// Reads a book aloud and reports the word being spoken, so the ribbon can lie under it.
@MainActor
@Observable
final class Reader: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var document: Document?
    private(set) var chapterIndex = 0 {
        didSet { refreshFacets() }
    }
    private(set) var chapters: [Chapter] = []
    /// The current chapter as timed spans (times are estimates until spoken).
    private(set) var text = TimedText()
    var currentIndex: Int? {
        didSet { refreshFacets() }
    }
    /// Coarse position facets, republished ONLY when they change (P2):
    /// progress and time-left for views that must not re-run per word.
    private(set) var progressPermille: Int = 0
    private(set) var minutesLeft: Int = 0
    /// The characters of a dialogue and their voices. Nil for an ordinary book.
    var cast: Cast?
    /// The current chapter's turns. Empty for an ordinary chapter.
    private(set) var turns: [Turn] = []
    /// The speaker label of the turn being read, nil for narration or a book.
    private(set) var currentSpeaker: String?
    var isDialogue: Bool { !turns.isEmpty }
    /// The span index speech is prepared through: the real buffer ahead of
    /// the head. Kokoro reports scheduled audio; the Apple path reports the
    /// enqueued utterances. Changes per sentence, never per word.
    private(set) var bufferedThrough: Int?
    private(set) var isSpeaking = false
    private(set) var isPaused = false
    var voice: AVSpeechSynthesisVoice?
    var rateMultiplier: Double = 1.0
    /// Which engine reads: Apple's synthesizer or Kokoro on-device.
    /// Synced from Settings by Engine and by the settings screen.
    var voiceEngine: Settings.VoiceEngineChoice = .apple
    /// The chosen Kokoro voice (e.g. "af_heart").
    var kokoroVoiceID: String = KokoroVoice.defaultVoiceID
    /// One long-lived Kokoro player for every session (P7): its engine
    /// stays attached and warm instead of being rebuilt per play.
    private let kokoro = KokoroPlayer()
    private var kokoroGeneration = 0
    /// True while the current playback is Kokoro-driven.
    private var kokoroActive = false
    /// A Kokoro start deferred because the user paused during model load.
    private var pendingKokoroStart: (() -> Void)?
    /// Minutes until the reader stops on its own. Nil means no sleep timer.
    var sleepAt: Date?

    /// Persistence callback, fired at SAVE POINTS ONLY (pause, stop,
    /// chapter change, explicit jumps, backgrounding) — never per word.
    /// The live position lives in this Reader; the model is written rarely.
    var onSavePoint: ((Document, Int, Int) -> Void)?

    /// Created on first use rather than at app launch (P19).
    @ObservationIgnored
    private lazy var synthesizer: AVSpeechSynthesizer = {
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        return synthesizer
    }()
    private var offsets: [Int] = []
    private var sleepTimer: Timer?
    /// Speech is enqueued one sentence at a time (a whole chapter as a single
    /// utterance starts slowly and reads flat). Each chunk remembers the
    /// character offset it starts at, so word-boundary callbacks still map to
    /// the chapter. The generation tag keeps delegate callbacks from a
    /// cancelled queue from touching the queue that replaced it.
    private var chunkCharBase: [ObjectIdentifier: Int] = [:]
    private var chunkGeneration: [ObjectIdentifier: Int] = [:]
    /// One unit of speech: a sentence, or less when a turn ends mid-sentence.
    struct SpeechChunk {
        var start: Int
        var end: Int
        var text: String
        /// Who says it. Nil for narration or an ordinary book.
        var speaker: String?
        /// The last chunk of a turn: a breath follows it.
        var endsTurn: Bool
    }

    /// Rolling window (P9): never more than three utterances enqueued;
    /// `didFinish` tops the window up from `pendingChunks`.
    private var pendingChunks: [SpeechChunk] = []
    private var enqueuedChunkIDs: [ObjectIdentifier] = []
    private var totalChunkCount = 0
    private var finishedChunkCount = 0
    private var playGeneration = 0
    private var notesLastID: ObjectIdentifier?

    // MARK: Loading

    func load(_ document: Document) {
        stop()
        self.document = document
        chapters = document.chapters
        cast = document.cast
        chapterIndex = min(document.chapterIndex, max(0, chapters.count - 1))
        loadChapter(chapterIndex)
        currentIndex = min(document.spanIndex, max(0, text.spans.count - 1))
        // Warm the session now, so the play tap later is instant. Reading
        // uses the record-capable session shape (see AudioSession) so a
        // hold-to-note never reconfigures the session mid-book.
        AudioSession.configureAsync(.record)
    }

    private func loadChapter(_ index: Int) {
        guard chapters.indices.contains(index) else {
            text = TimedText()
            turns = []
            return
        }
        turns = chapters[index].turns ?? []
        chapterIndex = index
        text = TimedText.tokenize(chapters[index].text)
        offsets = text.characterOffsets()
    }

    // MARK: Turns

    /// The index into `turns` of the turn being read.
    var currentTurnIndex: Int? {
        guard let currentIndex else { return nil }
        return turns.turnIndex(containing: currentIndex)
    }

    /// Moves to the start of the next (+1) or previous (−1) turn, across chapters.
    func skipTurn(_ delta: Int) {
        guard isDialogue else {
            skip(delta < 0 ? -15 : 15)
            return
        }
        let current = currentTurnIndex ?? 0
        let target = current + delta
        if target < 0 {
            if chapterIndex > 0 { goToChapter(chapterIndex - 1) } else { jump(to: 0) }
            return
        }
        if target >= turns.count {
            if chapterIndex < chapters.count - 1 { goToChapter(chapterIndex + 1) }
            return
        }
        jump(to: turns[target].start)
    }

    /// Jumps to the next line spoken by `speaker`, searching forward from the
    /// current turn, then from the chapter's start.
    func jumpToNextTurn(of speaker: String) {
        guard isDialogue else { return }
        let from = (currentTurnIndex ?? -1) + 1
        let ordered = Array(turns[min(from, turns.count)...]) + Array(turns[..<min(from, turns.count)])
        guard let next = ordered.first(where: { $0.speaker == speaker }) else { return }
        jump(to: next.start)
    }

    private func jump(to index: Int) {
        if isSpeaking && !isPaused {
            play(from: index)
        } else {
            currentIndex = index
            savePoint()
        }
    }

    /// The cast member who speaks `speaker`, with the reader's own voices as the fallback.
    func member(for speaker: String?) -> CastMember? {
        cast?.member(for: speaker)
    }

    func goToChapter(_ index: Int) {
        guard chapters.indices.contains(index) else { return }
        let wasSpeaking = isSpeaking && !isPaused
        synthesizer.stopSpeaking(at: .immediate)
        kokoro.stop()
        kokoroActive = false
        isSpeaking = false
        isPaused = false
        loadChapter(index)
        currentIndex = 0
        savePoint()
        if wasSpeaking { play(from: 0) }
    }

    // MARK: Playback

    func play(from index: Int? = nil) {
        guard let document, !text.spans.isEmpty else { return }
        try? AudioSession.configure(.record)
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        kokoro.stop()
        kokoroActive = false
        pendingKokoroStart = nil
        playGeneration += 1
        chunkCharBase.removeAll()
        chunkGeneration.removeAll()
        pendingChunks = []
        enqueuedChunkIDs = []
        totalChunkCount = 0
        finishedChunkCount = 0
        notesLastID = nil
        bufferedThrough = nil
        let start = min(max(index ?? currentIndex ?? document.spanIndex, 0), text.spans.count - 1)
        currentIndex = start
        isSpeaking = true
        isPaused = false
        if voiceEngine == .kokoro, KokoroVoice.shared.modelsPresent {
            startKokoro(from: start)
        } else {
            enqueueSentences(from: start)
        }
        savePoint()
    }

    /// Sentence-sized chunks over the chapter's spans — one chunk per
    /// utterance on the Apple path, one per synthesized buffer on the
    /// Kokoro path. A whole chapter as a single unit starts slowly and
    /// reads flat, so both engines work a sentence at a time. In a dialogue
    /// a chunk never crosses a turn, so every chunk has one speaker.
    private func sentenceChunks(from start: Int) -> [SpeechChunk] {
        let spans = text.spans
        var chunks: [SpeechChunk] = []
        var i = start
        var turnCursor = turns.turnIndex(containing: start) ?? 0
        while i < spans.count {
            // The turn this chunk belongs to, and where it must stop.
            var speaker: String?
            var limit = spans.count
            if !turns.isEmpty {
                while turnCursor < turns.count, turns[turnCursor].end <= i { turnCursor += 1 }
                if turnCursor < turns.count {
                    speaker = turns[turnCursor].speaker
                    limit = turns[turnCursor].end
                }
            }
            var j = i
            var chars = 0
            while j < limit {
                let piece = spans[j].text
                chars += piece.count
                j += 1
                if Self.endsSentence(piece) || piece.contains("\n") || chars >= 340 || j - i >= 90 { break }
            }
            if j == i { j = i + 1 }
            let string = spans[i..<j].map(\.text).joined()
            if !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chunks.append(SpeechChunk(start: i, end: j, text: string, speaker: speaker, endsTurn: !turns.isEmpty && j >= limit))
            }
            i = j
        }
        return chunks
    }

    /// The breath between two speakers.
    static let turnGap: TimeInterval = 0.45

    private func enqueueSentences(from start: Int) {
        pendingChunks = sentenceChunks(from: start)
        totalChunkCount = pendingChunks.count
        finishedChunkCount = 0
        enqueuedChunkIDs = []
        refillWindow()
    }

    /// Keeps the synthesizer's queue at three utterances: enough that a
    /// finished sentence never leaves a gap, never a whole chapter.
    private func refillWindow() {
        while enqueuedChunkIDs.count < 3, !pendingChunks.isEmpty {
            let chunk = pendingChunks.removeFirst()
            let utterance = makeUtterance(for: chunk)
            let id = ObjectIdentifier(utterance)
            chunkCharBase[id] = offsets.indices.contains(chunk.start) ? offsets[chunk.start] : 0
            chunkGeneration[id] = playGeneration
            enqueuedChunkIDs.append(id)
            if (bufferedThrough ?? 0) < chunk.end { bufferedThrough = chunk.end }
            synthesizer.speak(utterance)
        }
    }

    private static func endsClause(_ piece: String) -> Bool {
        let t = piece.trimmingCharacters(in: .whitespaces)
        guard let last = t.last else { return false }
        return last == "," || last == ";" || last == ":" || last == "—"
    }

    /// The Kokoro path: the same sentence chunks, synthesized on-device
    /// and played by KokoroPlayer. Any failure — models gone, a voice
    /// pack missing, a synthesis error — hands the book back to the Apple
    /// voice at the current word instead of stranding the listener.
    private func startKokoro(from start: Int) {
        var rawChunks = sentenceChunks(from: start)
        // Split the first chunk at its first clause (P7): the first buffer
        // is what the listener waits on, and a short clause synthesizes in
        // a fraction of the time a full sentence takes.
        if let first = rawChunks.first, first.end - first.start > 1 {
            let spans = text.spans
            var chars = 0
            var split: Int?
            for i in first.start..<first.end {
                chars += spans[i].text.count
                if chars >= 20, i + 1 < first.end, Self.endsClause(spans[i].text) {
                    split = i + 1
                    break
                }
                if chars > 60 { break }
            }
            if let split {
                let head = SpeechChunk(start: first.start, end: split, text: spans[first.start..<split].map(\.text).joined(), speaker: first.speaker, endsTurn: false)
                let tail = SpeechChunk(start: split, end: first.end, text: spans[split..<first.end].map(\.text).joined(), speaker: first.speaker, endsTurn: first.endsTurn)
                rawChunks.replaceSubrange(0...0, with: [head, tail])
            }
        }
        let narratorVoice = kokoroVoiceID
        let baseSpeed = min(max(rateMultiplier, 0.5), 2.0)
        let chunks = rawChunks.map { chunk in
            let who = member(for: chunk.speaker)
            return KokoroPlayer.Chunk(
                text: chunk.text,
                spanStart: chunk.start,
                wordWeights: text.spans[chunk.start..<chunk.end].map { max(1, $0.text.trimmingCharacters(in: .whitespaces).count) },
                voice: who?.kokoroVoiceID ?? narratorVoice,
                speed: Float(min(max(baseSpeed * (who?.pace ?? 1), 0.5), 2.0)),
                gapAfter: chunk.endsTurn ? Self.turnGap : 0
            )
        }
        guard !chunks.isEmpty else {
            enqueueSentences(from: start)
            return
        }
        kokoroGeneration += 1
        let gen = kokoroGeneration
        kokoroActive = true
        let voiceID = narratorVoice
        let castVoices = Array(Set(chunks.map(\.voice)).subtracting([narratorVoice]))
        let player = kokoro
        player.onWord = { [weak self] span in
            guard let self, self.kokoroActive, gen == self.kokoroGeneration, self.isSpeaking else { return }
            if span != self.currentIndex {
                self.currentIndex = span
            }
        }
        player.onQueueFinished = { [weak self] in
            guard let self, self.kokoroActive, gen == self.kokoroGeneration else { return }
            self.kokoroActive = false
            self.chapterFinished()
        }
        player.onBuffered = { [weak self] through in
            guard let self, self.kokoroActive, gen == self.kokoroGeneration else { return }
            if (self.bufferedThrough ?? 0) < through { self.bufferedThrough = through }
        }
        player.onError = { [weak self] _ in
            guard let self, self.kokoroActive, gen == self.kokoroGeneration, self.isSpeaking else { return }
            self.kokoroActive = false
            self.enqueueSentences(from: self.currentIndex ?? start)
        }
        Task { [weak self] in
            let ready = await KokoroVoice.shared.prepareIfDownloaded(voice: voiceID)
            // A cast needs its voice packs too; fetched once, then cached by the SDK.
            for voice in castVoices { await KokoroVoice.shared.preload(voice: voice) }
            guard let self, self.kokoroActive, gen == self.kokoroGeneration, self.isSpeaking else { return }
            guard ready else {
                self.kokoroActive = false
                self.enqueueSentences(from: start)
                return
            }
            if self.isPaused {
                // Paused while the models loaded: hold the start for resume.
                self.pendingKokoroStart = {
                    player.start(chunks: chunks) { chunk in
                        try await KokoroVoice.shared.synthesize(text: chunk.text, voice: chunk.voice, speed: chunk.speed)
                    }
                }
                return
            }
            player.start(chunks: chunks) { chunk in
                try await KokoroVoice.shared.synthesize(text: chunk.text, voice: chunk.voice, speed: chunk.speed)
            }
        }
    }

    /// The current chapter's audio ended: open the next one, or stop.
    private func chapterFinished() {
        if chapterIndex < chapters.count - 1, document != nil, !text.spans.isEmpty {
            loadChapter(chapterIndex + 1)
            currentIndex = 0
            play(from: 0)
        } else {
            isSpeaking = false
            isPaused = false
        }
    }

    private static func endsSentence(_ piece: String) -> Bool {
        let t = piece.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = t.last else { return false }
        if last == "." || last == "!" || last == "?" || last == "…" { return true }
        // Closing quotes after terminal punctuation still end the sentence.
        if t.count >= 2 {
            let prev = t[t.index(t.endIndex, offsetBy: -2)]
            return (last == "\"" || last == "”" || last == "'") && (prev == "." || prev == "!" || prev == "?")
        }
        return false
    }

    private func makeUtterance(_ string: String, voiceOverride: AVSpeechSynthesisVoice? = nil) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: string)
        utterance.voice = voiceOverride ?? voice ?? Self.bestDefaultVoice()
        utterance.rate = Self.rate(for: rateMultiplier)
        utterance.pitchMultiplier = 1.02
        utterance.prefersAssistiveTechnologySettings = false
        return utterance
    }

    /// An utterance in the chunk's speaker's voice, pitch and pace, with a
    /// breath after the last chunk of a turn.
    private func makeUtterance(for chunk: SpeechChunk) -> AVSpeechUtterance {
        let who = member(for: chunk.speaker)
        let whoVoice = who?.voiceIdentifier.flatMap { AVSpeechSynthesisVoice(identifier: $0) }
        let utterance = makeUtterance(chunk.text, voiceOverride: who?.isNarrator == false ? whoVoice : nil)
        if let who, !who.isNarrator {
            utterance.pitchMultiplier = Float(min(max(who.pitch, 0.5), 2.0)) * 1.02
            utterance.rate = Self.rate(for: rateMultiplier * who.pace)
        }
        if chunk.endsTurn { utterance.postUtteranceDelay = Self.turnGap }
        return utterance
    }

    func pause() {
        guard isSpeaking, !isPaused else { return }
        if kokoroActive {
            kokoro.pause()
            isPaused = true
            savePoint()
            return
        }
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
        savePoint()
    }

    func resume() {
        guard isSpeaking, isPaused else { return }
        try? AudioSession.configure(.record)
        if kokoroActive {
            if let pending = pendingKokoroStart {
                pendingKokoroStart = nil
                pending()
            } else {
                kokoro.resume()
            }
            isPaused = false
            return
        }
        if !synthesizer.continueSpeaking() {
            play(from: currentIndex)
        }
        isPaused = false
    }

    func toggle() {
        if !isSpeaking { play() } else if isPaused { resume() } else { pause() }
    }

    func stop() {
        savePoint()
        synthesizer.stopSpeaking(at: .immediate)
        playGeneration += 1
        kokoro.stop()
        kokoroActive = false
        pendingKokoroStart = nil
        kokoroGeneration += 1
        chunkCharBase.removeAll()
        chunkGeneration.removeAll()
        pendingChunks = []
        enqueuedChunkIDs = []
        totalChunkCount = 0
        finishedChunkCount = 0
        notesLastID = nil
        bufferedThrough = nil
        isSpeaking = false
        isPaused = false
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepAt = nil
    }

    /// Stops AND forgets the loaded book. Deletion goes through here:
    /// `stop()` alone leaves `document` set, which kept a deleted book
    /// alive as Engine's continue target (and on Pocket's strip).
    func unload() {
        stop()
        document = nil
        chapters = []
        cast = nil
        turns = []
        currentSpeaker = nil
        text = TimedText()
        currentIndex = nil
        chapterIndex = 0
        progressPermille = 0
        minutesLeft = 0
    }

    /// Skips about `seconds` of speech, forward or back.
    func skip(_ seconds: TimeInterval) {
        let wordsPerSecond = 2.6 * rateMultiplier
        let delta = Int(seconds * wordsPerSecond)
        let target = (currentIndex ?? 0) + delta
        if target < 0, chapterIndex > 0 {
            goToChapter(chapterIndex - 1)
            return
        }
        if target >= text.spans.count, chapterIndex < chapters.count - 1 {
            goToChapter(chapterIndex + 1)
            return
        }
        let clamped = min(max(target, 0), max(0, text.spans.count - 1))
        if isSpeaking && !isPaused {
            play(from: clamped)
        } else {
            currentIndex = clamped
            savePoint()
        }
    }

    func setRate(_ multiplier: Double) {
        rateMultiplier = multiplier
        refreshFacets()
        if isSpeaking && !isPaused { play(from: currentIndex) }
    }

    func setSleep(minutes: Int?) {
        sleepTimer?.invalidate()
        sleepTimer = nil
        guard let minutes else {
            sleepAt = nil
            return
        }
        let at = Date().addingTimeInterval(Double(minutes) * 60)
        sleepAt = at
        sleepTimer = Timer.commonScheduled(withTimeInterval: Double(minutes) * 60, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.pause()
                self?.sleepAt = nil
            }
        }
    }

    /// Reads a list of notes aloud, in order, in the chosen voice.
    func speakNotes(_ notes: [Note], voice: AVSpeechSynthesisVoice?) {
        stop()
        for note in notes.sorted(by: { ($0.chapterIndex, $0.spanIndex) < ($1.chapterIndex, $1.spanIndex) }) {
            let utterance = makeUtterance(note.text, voiceOverride: voice ?? self.voice)
            utterance.postUtteranceDelay = 0.6
            notesLastID = ObjectIdentifier(utterance)
            synthesizer.speak(utterance)
        }
        isSpeaking = true
        isPaused = false
    }

    var secondsLeftInChapter: TimeInterval {
        let remaining = max(0, text.spans.count - (currentIndex ?? 0))
        return Double(remaining) / (2.6 * rateMultiplier)
    }

    // MARK: Voices

    static func rate(for multiplier: Double) -> Float {
        let base = Double(AVSpeechUtteranceDefaultSpeechRate)
        let maxRate = Double(AVSpeechUtteranceMaximumSpeechRate)
        let minRate = Double(AVSpeechUtteranceMinimumSpeechRate)
        let r = multiplier >= 1 ? base + (maxRate - base) * (multiplier - 1) / 1.5 : minRate + (base - minRate) * multiplier
        return Float(min(max(r, minRate), maxRate))
    }

    private static var bestDefaultVoiceCache: AVSpeechSynthesisVoice??

    /// Clears the memoized best voice so the next lookup re-scans.
    static func refreshBestVoiceCache() {
        bestDefaultVoiceCache = nil
    }

    static func bestDefaultVoice() -> AVSpeechSynthesisVoice? {
        if let cached = bestDefaultVoiceCache { return cached }
        let computed = computeBestDefaultVoice()
        bestDefaultVoiceCache = computed
        return computed
    }

    /// Apple voices fit for a cast: the current language, best quality first,
    /// no novelty voices and not the user's Personal Voice.
    static func castableVoices() -> [AVSpeechSynthesisVoice] {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(code) && !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice) }
            .sorted { a, b in
                if a.quality != b.quality { return a.quality.rawValue > b.quality.rawValue }
                return a.name < b.name
            }
    }

    private static func computeBestDefaultVoice() -> AVSpeechSynthesisVoice? {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        let exact = Locale.current.identifier(.bcp47)
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix(code) && !$0.voiceTraits.contains(.isNoveltyVoice)
        }
        // Best quality first; within a tier prefer the device's exact locale.
        for quality in [AVSpeechSynthesisVoiceQuality.premium, .enhanced, .default] {
            let tier = voices.filter { $0.quality == quality }
            if let exactMatch = tier.first(where: { $0.language == exact }) { return exactMatch }
            if let any = tier.first { return any }
        }
        return AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
    }

    private func savePoint() {
        guard let document, let currentIndex else { return }
        onSavePoint?(document, chapterIndex, currentIndex)
    }

    /// For the app going to the background: the live position becomes the
    /// stored position.
    func savePosition() {
        savePoint()
    }

    /// Recomputes the coarse facets from the live position, assigning only
    /// on change so observers of the facets don't fire per word (P2).
    private func refreshFacets() {
        guard let document else { return }
        let speaker = currentTurnIndex.map { turns[$0].speaker } ?? nil
        if speaker != currentSpeaker { currentSpeaker = speaker }
        let starts = document.chapterSpanStarts
        guard starts.count > 1 else { return }
        let total = starts[starts.count - 1]
        guard total > 0 else { return }
        let chapter = min(max(chapterIndex, 0), starts.count - 2)
        let global = starts[chapter] + (currentIndex ?? 0)
        let permille = min(1000, max(0, global * 1000 / total))
        if permille != progressPermille { progressPermille = permille }
        let left = Int(ceil(Double(max(0, total - global)) / (2.6 * rateMultiplier) / 60))
        if left != minutesLeft { minutesLeft = left }
    }

    // MARK: AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let location = characterRange.location
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard self.isSpeaking,
                  self.chunkGeneration[id] == self.playGeneration,
                  let charBase = self.chunkCharBase[id] else { return }
            if let i = TimedText.spanIndex(forOffset: charBase + location, offsets: self.offsets) {
                if i != self.currentIndex {
                    self.currentIndex = i
                }
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            if id == self.notesLastID {
                self.notesLastID = nil
                if !synthesizer.isSpeaking {
                    self.isSpeaking = false
                    self.isPaused = false
                }
                return
            }
            guard self.chunkGeneration[id] == self.playGeneration else { return }
            self.chunkCharBase[id] = nil
            self.chunkGeneration[id] = nil
            self.enqueuedChunkIDs.removeAll { $0 == id }
            self.finishedChunkCount += 1
            guard self.isSpeaking else { return }
            self.refillWindow()
            // Sentence chunks finish one by one; the chapter ends only
            // when every chunk has finished and the queue has drained.
            if self.finishedChunkCount >= self.totalChunkCount, !synthesizer.isSpeaking {
                self.chapterFinished()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // Cancelled by play(from:) or stop(); the chunk maps were already
        // cleared there, and the generation tag makes any late cleanup a no-op.
    }
}
