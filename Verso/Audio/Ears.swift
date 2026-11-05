import Foundation
import AVFoundation

/// Anything that turns speech into timed text. Two implementations ship:
/// `AppleEars` (SpeechAnalyzer, iOS 26+) and `ClassicEars` (SFSpeechRecognizer).
protocol Ears: AnyObject {
    var name: String { get }

    /// Begins a live session. `onUpdate` receives the whole transcript so far,
    /// final words first, still-settling words last. It may be called from any thread.
    func startLive(inputFormat: AVAudioFormat, onUpdate: @escaping @Sendable (TimedText) -> Void) async throws

    /// Feeds one buffer of live audio. Called from the audio thread.
    func feed(_ buffer: AVAudioPCMBuffer)

    /// Ends the live session and returns the final transcript.
    func finishLive() async -> TimedText

    /// Transcribes a whole audio file.
    func transcribe(file url: URL) async throws -> TimedText
}

enum EarsError: LocalizedError {
    case notAuthorized
    case assetsUnavailable
    case unavailable

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Speech recognition is not allowed. Turn it on in Settings."
        case .assetsUnavailable: return "The speech model for your language is not installed yet."
        case .unavailable: return "Speech recognition is not available on this device."
        }
    }
}

extension Ears {
    /// Default file transcription: replay the file through the live path.
    func transcribeByReplaying(file url: URL) async throws -> TimedText {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let box = TranscriptBox()
        try await startLive(inputFormat: format) { text in box.latest = text }
        let frames: AVAudioFrameCount = 8192
        while audioFile.framePosition < audioFile.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { break }
            try audioFile.read(into: buffer, frameCount: frames)
            if buffer.frameLength == 0 { break }
            feed(buffer)
        }
        return await finishLive()
    }
}

/// A thread-safe holder for the latest transcript.
final class TranscriptBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = TimedText()

    var latest: TimedText {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
    }
}

/// Converts live audio buffers to the format an engine wants.
final class BufferConverter {
    private var converter: AVAudioConverter?
    private let target: AVAudioFormat

    init(target: AVAudioFormat) {
        self.target = target
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == target { return buffer }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
        }
        guard let converter else { return nil }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if status == .error || error != nil { return nil }
        return out.frameLength > 0 ? out : nil
    }
}
