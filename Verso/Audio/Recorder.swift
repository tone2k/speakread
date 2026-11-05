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
    var title = ""
    var elapsed: TimeInterval = 0
    var level: Float = 0
    /// Recent levels for the ribbon waveform, oldest first.
    var levels: [Float] = Array(repeating: 0, count: 64)
    var transcript = TimedText()
    var marks: [Mark] = []
    var earsName = ""

    private let engine = AVAudioEngine()
    private let sink = CaptureSink()
    private var ears: Ears?
    private var fileName: String?
    private var ticker: Timer?

    func start(ears: Ears, title: String) async throws {
        guard !isRecording else { return }
        try AudioSession.configure(.record)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let name = UUID().uuidString + ".caf"
        let file = try AVAudioFile(forWriting: AudioStore.url(for: name), settings: format.settings)

        try await ears.startLive(inputFormat: format) { [weak self] text in
            Task { @MainActor in self?.transcript = text }
        }

        sink.begin(file: file, ears: ears)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [sink] buffer, _ in
            sink.handle(buffer)
        }
        engine.prepare()
        try engine.start()

        self.ears = ears
        self.earsName = ears.name
        self.fileName = name
        self.title = title
        self.transcript = TimedText()
        self.marks = []
        self.elapsed = 0
        self.levels = Array(repeating: 0, count: 64)
        self.isRecording = true
        self.isPaused = false

        ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
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
        guard isRecording else { return nil }
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

    func begin(file: AVAudioFile, ears: Ears) {
        lock.lock()
        self.file = file
        self.ears = ears
        self.frames = 0
        self.sampleRate = file.processingFormat.sampleRate
        self.currentLevel = 0
        lock.unlock()
    }

    func end() {
        lock.lock()
        file = nil
        ears = nil
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
