import Foundation
import AVFoundation
import Speech

/// Speech to text with SFSpeechRecognizer. Works on every iPhone and gives
/// segment timestamps. Prefers on-device recognition when the device supports it.
final class ClassicEars: NSObject, Ears, @unchecked Sendable {
    let name = "Apple dictation"

    private let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private let lock = NSLock()
    private var committed: [TimedSpan] = []
    private var volatile: [TimedSpan] = []
    private var onUpdate: (@Sendable (TimedText) -> Void)?
    private var offset: TimeInterval = 0
    private var fedSeconds: TimeInterval = 0
    private var live = false
    private var finishContinuation: CheckedContinuation<Void, Never>?

    func startLive(inputFormat: AVAudioFormat, onUpdate: @escaping @Sendable (TimedText) -> Void) async throws {
        let status = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard status == .authorized else { throw EarsError.notAuthorized }
        guard let recognizer, recognizer.isAvailable else { throw EarsError.unavailable }

        lock.lock()
        committed = []
        volatile = []
        offset = 0
        fedSeconds = 0
        live = true
        self.onUpdate = onUpdate
        lock.unlock()
        beginRequest()
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let request = self.request
        fedSeconds += Double(buffer.frameLength) / buffer.format.sampleRate
        lock.unlock()
        request?.append(buffer)
    }

    func finishLive() async -> TimedText {
        lock.lock()
        live = false
        let request = self.request
        lock.unlock()
        request?.endAudio()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.lock()
            if task == nil {
                lock.unlock()
                c.resume()
                return
            }
            finishContinuation = c
            lock.unlock()
            // Do not wait forever for the final result.
            DispatchQueue.global().asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.resumeFinish()
            }
        }
        lock.lock()
        let text = TimedText(spans: committed + volatile).renumbered()
        task?.cancel()
        task = nil
        self.request = nil
        onUpdate = nil
        lock.unlock()
        return text
    }

    func transcribe(file url: URL) async throws -> TimedText {
        let status = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard status == .authorized else { throw EarsError.notAuthorized }
        guard let recognizer, recognizer.isAvailable else { throw EarsError.unavailable }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<TimedText, Error>) in
            var done = false
            _ = recognizer.recognitionTask(with: request) { result, error in
                if done { return }
                if let error {
                    done = true
                    c.resume(throwing: error)
                    return
                }
                if let result, result.isFinal {
                    done = true
                    c.resume(returning: TimedText(spans: Self.spans(from: result.bestTranscription, offset: 0, isFinal: true)))
                }
            }
        }
    }

    // MARK: Requests

    private func beginRequest() {
        guard let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        lock.lock()
        self.request = request
        lock.unlock()

        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            var shouldRestart = false
            lock.lock()
            if let result {
                let spans = Self.spans(from: result.bestTranscription, offset: offset, isFinal: result.isFinal)
                if result.isFinal {
                    committed.append(contentsOf: spans)
                    volatile = []
                    offset += fedSeconds
                    fedSeconds = 0
                    shouldRestart = live
                } else {
                    volatile = spans
                }
            }
            if error != nil {
                shouldRestart = live
                offset += fedSeconds
                fedSeconds = 0
            }
            let text = TimedText(spans: committed + volatile).renumbered()
            let callback = onUpdate
            let finished = (result?.isFinal == true || error != nil) && !live
            lock.unlock()
            callback?(text)
            if finished {
                resumeFinish()
            } else if shouldRestart {
                beginRequest()
            }
        }
        lock.lock()
        self.task = task
        lock.unlock()
    }

    private func resumeFinish() {
        lock.lock()
        let c = finishContinuation
        finishContinuation = nil
        lock.unlock()
        c?.resume()
    }

    private static func spans(from transcription: SFTranscription, offset: TimeInterval, isFinal: Bool) -> [TimedSpan] {
        transcription.segments.enumerated().map { i, segment in
            TimedSpan(
                id: i,
                text: segment.substring + " ",
                start: offset + segment.timestamp,
                end: offset + segment.timestamp + segment.duration,
                confidence: segment.confidence,
                isFinal: isFinal
            )
        }
    }
}
