import Foundation
import AVFoundation
import Observation

/// Captures the microphone, writes a file, and feeds the Ears. The screens read
/// `elapsed`, `levels` and `transcript` and never touch audio.
@MainActor
@Observable
final class Recorder {
    private(set) var isRecording = false
    private(set) var isPaused = false
    /// True while a stop is still finalizing the transcript.
    private(set) var isFinishing = false
    var title = ""
    var elapsed: TimeInterval = 0
    var level: Float = 0
    /// Recent levels for the ribbon waveform, oldest first.
    var levels: [Float] = Array(repeating: 0, count: 64)
    var transcript = TimedText()
    /// Final spans only, append-only (P11): once a span lands here it never
    /// changes, so the live view's stable prefix never re-measures.
    private(set) var finalText = TimedText()
    /// The still-settling words as one string, replaced per update (P11).
    private(set) var tailText = ""
    var marks: [Mark] = []
    var earsName = ""

    private let engine = AVAudioEngine()
    private let sink = CaptureSink()
    private var ears: Ears?
    private var fileName: String?
    private var ticker: Timer?
    /// Incremented by every start and every stop: an in-flight start whose
    /// token no longer matches knows a stop raced it and must tear down
    /// instead of turning the mic on (the start/stop race).
    private var startToken = 0
    private var isStarting = false

    func start(ears: Ears, title: String) async throws {
        guard !isRecording, !isFinishing, !isStarting else { return }
        startToken += 1
        let token = startToken
        isStarting = true
        defer { isStarting = false }
        // Flip state first, before any setup: the record button has to feel
        // instant. Session setup and the speech engine's asset check can take
        // a second; they run after this, and the state rolls back on failure.
        self.ears = ears
        self.earsName = ears.name
        self.fileName = nil
        self.title = title
        self.transcript = TimedText()
        self.finalText = TimedText()
        self.tailText = ""
        self.marks = []
        self.elapsed = 0
        self.levels = Array(repeating: 0, count: 64)
        self.isRecording = true
        self.isPaused = false

        do {
            try AudioSession.configure(.record)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            let name = UUID().uuidString + ".caf"
            let file = try AVAudioFile(forWriting: AudioStore.url(for: name), settings: format.settings)
            self.fileName = name

            // Mic live FIRST (P20): the tap, the file and the engine start
            // now; the ears' session — the slow part — starts after, and a
            // ring buffer in the sink holds the opening words for it.
            sink.begin(file: file)
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [sink] buffer, _ in
                sink.handle(buffer)
            }
            engine.prepare()
            try engine.start()

            try await ears.startLive(inputFormat: format) { [weak self] text in
                Task { @MainActor in self?.absorb(text) }
            }
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            sink.end()
            isRecording = false
            isPaused = false
            self.ears = nil
            if let fileName { AudioStore.remove(fileName) }
            self.fileName = nil
            throw error
        }

        guard token == startToken, isRecording else {
            // A stop landed while the ears were starting. Tear everything
            // down here — the stop already returned, so this continuation
            // is the only place that can — and drop the partial file
            // instead of leaving the mic on.
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            sink.end()
            _ = await ears.finishLive()
            self.ears = nil
            if let fileName { AudioStore.remove(fileName) }
            self.fileName = nil
            AudioSession.deactivate()
            return
        }
        sink.attach(ears: ears)

        ticker = Timer.commonScheduled(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// Splits one delivered transcript into the append-only final prefix
    /// and the volatile tail (P11). Engines deliver final words first,
    /// settling words last, so finals only ever grow.
    private func absorb(_ text: TimedText) {
        transcript = text
        let finals = text.spans.filter(\.isFinal)
        if finals.count > finalText.spans.count {
            finalText.spans.append(contentsOf: finals[finalText.spans.count...])
        } else if finals.count < finalText.spans.count {
            // The engine restarted its count (a new request): resync.
            finalText.spans = finals
        }
        tailText = text.spans.filter { !$0.isFinal }.map(\.text).joined()
    }

    private func tick() {
        guard isRecording else { return }
        elapsed = sink.seconds
        let l = sink.level
        level = l
        levels.removeFirst()
        levels.append(l)
    }

    func pause() {
        guard isRecording, !isPaused else { return }
        engine.pause()
        isPaused = true
    }

    func resume() {
        guard isRecording, isPaused else { return }
        try? engine.start()
        isPaused = false
    }

    func mark(_ label: String? = nil) {
        guard isRecording else { return }
        let n = marks.count + 1
        marks.append(Mark(time: elapsed, label: label ?? "Mark \(n)"))
    }

    /// Stops and returns the finished document, or nil if nothing was recorded.
    func stop() async -> Document? {
        // Invalidate any in-flight start first: if setup is still running,
        // its continuation owns the teardown (see start()).
        startToken += 1
        guard isRecording, !isFinishing else { return nil }
        if isStarting {
            isRecording = false
            isPaused = false
            return nil
        }
        isFinishing = true
        defer { isFinishing = false }
        ticker?.invalidate()
        ticker = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        sink.end()
        isRecording = false
        isPaused = false

        let text = await ears?.finishLive() ?? transcript
        transcript = text
        let document = Document(kind: .recording, title: title)
        document.audioFileName = fileName
        document.duration = max(elapsed, text.duration)
        document.transcript = text
        document.marks = marks
        ears = nil
        AudioSession.deactivate()
        if elapsed < 0.5 && text.isEmpty {
            if let fileName { AudioStore.remove(fileName) }
            return nil
        }
        return document
    }
}

/// Runs on the audio thread: writes the file, measures the level, feeds the Ears.
final class CaptureSink: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var ears: Ears?
    private var frames: AVAudioFramePosition = 0
    private var sampleRate: Double = 48_000
    private var currentLevel: Float = 0
    /// Buffers captured before the ears' session was ready (P20). Without
    /// this ring, the words spoken during `startLive` never reached the
    /// transcriber: the file had them, the transcript didn't.
    private var pending: [AVAudioPCMBuffer] = []
    private var pendingFrames: AVAudioFramePosition = 0

    func begin(file: AVAudioFile) {
        lock.lock()
        self.file = file
        self.ears = nil
        self.frames = 0
        self.sampleRate = file.processingFormat.sampleRate
        self.currentLevel = 0
        self.pending = []
        self.pendingFrames = 0
        lock.unlock()
    }

    /// Hands the sink its ears once their session is live, replaying the
    /// ring buffer into them in order, under the lock so no live buffer
    /// can overtake the replay.
    func attach(ears: Ears) {
        lock.lock()
        self.ears = ears
        let buffered = pending
        pending = []
        pendingFrames = 0
        for buffer in buffered {
            ears.feed(buffer)
        }
        lock.unlock()
    }

    func end() {
        lock.lock()
        file = nil
        ears = nil
        pending = []
        pendingFrames = 0
        lock.unlock()
    }

    func handle(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let file = self.file
        let ears = self.ears
        lock.unlock()
        guard let file else { return }
        try? file.write(from: buffer)
        let rms = Self.rms(of: buffer)
        lock.lock()
        frames += AVAudioFramePosition(buffer.frameLength)
        currentLevel = rms
        if ears == nil {
            // Keep at most ~6 seconds of unclaimed audio.
            pending.append(buffer)
            pendingFrames += AVAudioFramePosition(buffer.frameLength)
            while pendingFrames > AVAudioFramePosition(sampleRate * 6), !pending.isEmpty {
                pendingFrames -= AVAudioFramePosition(pending.removeFirst().frameLength)
            }
        }
        lock.unlock()
        ears?.feed(buffer)
    }

    var seconds: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return Double(frames) / sampleRate
    }

    /// 0...1, perceptual.
    var level: Float {
        lock.lock(); defer { lock.unlock() }
        let db = 20 * log10(max(currentLevel, 1e-6))
        return min(1, max(0, (db + 50) / 50))
    }

    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        let channel = data[0]
        for i in 0..<n { sum += channel[i] * channel[i] }
        return sqrt(sum / Float(n))
    }
}
