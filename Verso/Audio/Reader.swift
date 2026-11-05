import Foundation
import AVFoundation
import Observation

/// Reads a book aloud and reports the word being spoken, so the ribbon can lie under it.
@MainActor
@Observable
final class Reader: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var document: Document?
    private(set) var chapterIndex = 0
    private(set) var chapters: [Chapter] = []
    /// The current chapter as timed spans (times are estimates until spoken).
    private(set) var text = TimedText()
    var currentIndex: Int?
    private(set) var isSpeaking = false
    private(set) var isPaused = false
    var voice: AVSpeechSynthesisVoice?
    var rateMultiplier: Double = 1.0
    /// Minutes until the reader stops on its own. Nil means no sleep timer.
    var sleepAt: Date?

    var onProgress: ((Document, Int, Int) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var utteranceBase = 0
    private var offsets: [Int] = []
    private var sleepTimer: Timer?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: Loading

    func load(_ document: Document) {
        stop()
        self.document = document
        chapters = document.chapters
        chapterIndex = min(document.chapterIndex, max(0, chapters.count - 1))
        loadChapter(chapterIndex)
        currentIndex = min(document.spanIndex, max(0, text.spans.count - 1))
    }

    private func loadChapter(_ index: Int) {
        guard chapters.indices.contains(index) else {
            text = TimedText()
            return
        }
        chapterIndex = index
        text = TimedText.tokenize(chapters[index].text)
        offsets = text.characterOffsets()
    }

    func goToChapter(_ index: Int) {
        guard chapters.indices.contains(index) else { return }
        let wasSpeaking = isSpeaking && !isPaused
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        loadChapter(index)
        currentIndex = 0
        report()
        if wasSpeaking { play(from: 0) }
    }

    // MARK: Playback

    func play(from index: Int? = nil) {
        guard let document, !text.spans.isEmpty else { return }
        try? AudioSession.configure(.play)
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let start = min(max(index ?? currentIndex ?? document.spanIndex, 0), text.spans.count - 1)
        utteranceBase = start
        let string = text.spans[start...].map(\.text).joined()
        let utterance = AVSpeechUtterance(string: string)
        utterance.voice = voice ?? Self.bestDefaultVoice()
        utterance.rate = Self.rate(for: rateMultiplier)
        utterance.prefersAssistiveTechnologySettings = false
        currentIndex = start
        isSpeaking = true
        isPaused = false
        synthesizer.speak(utterance)
        report()
    }

    func pause() {
        guard isSpeaking, !isPaused else { return }
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
    }

    func resume() {
        guard isSpeaking, isPaused else { return }
        try? AudioSession.configure(.play)
        if !synthesizer.continueSpeaking() {
            play(from: currentIndex)
        }
        isPaused = false
    }

    func toggle() {
        if !isSpeaking { play() } else if isPaused { resume() } else { pause() }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepAt = nil
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
            report()
        }
    }

    func setRate(_ multiplier: Double) {
        rateMultiplier = multiplier
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
        sleepTimer = Timer.scheduledTimer(withTimeInterval: Double(minutes) * 60, repeats: false) { [weak self] _ in
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
            let utterance = AVSpeechUtterance(string: note.text)
            utterance.voice = voice ?? self.voice ?? Self.bestDefaultVoice()
            utterance.rate = Self.rate(for: rateMultiplier)
            utterance.postUtteranceDelay = 0.6
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

    static func bestDefaultVoice() -> AVSpeechSynthesisVoice? {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(code) }
        if let premium = voices.first(where: { $0.quality == .premium }) { return premium }
        if let enhanced = voices.first(where: { $0.quality == .enhanced }) { return enhanced }
        return voices.first ?? AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
    }

    private func report() {
        guard let document, let currentIndex else { return }
        onProgress?(document, chapterIndex, currentIndex)
    }

    // MARK: AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let location = characterRange.location
        Task { @MainActor in
            guard self.isSpeaking else { return }
            let baseOffset = self.offsets.indices.contains(self.utteranceBase) ? self.offsets[self.utteranceBase] : 0
            if let i = TimedText.spanIndex(forOffset: baseOffset + location, offsets: self.offsets) {
                if i != self.currentIndex {
                    self.currentIndex = i
                    self.report()
                }
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.isSpeaking, !synthesizer.isSpeaking else { return }
            if self.chapterIndex < self.chapters.count - 1, self.document != nil, !self.text.spans.isEmpty {
                self.loadChapter(self.chapterIndex + 1)
                self.currentIndex = 0
                self.play(from: 0)
            } else {
                self.isSpeaking = false
                self.isPaused = false
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // Cancelled by play(from:) or stop(); state is already set.
    }
}
