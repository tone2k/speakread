import Foundation
import AVFoundation
import CoreMedia
import Speech

/// Speech to text with Apple's on-device SpeechAnalyzer (iOS 26 and later).
/// Gives word-level time ranges, which is what the ribbon needs.
final class AppleEars: Ears, @unchecked Sendable {
    let name = "Apple on-device"

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: BufferConverter?
    private var resultsTask: Task<Void, Never>?

    private let lock = NSLock()
    private var committed: [TimedSpan] = []
    private var volatile: [TimedSpan] = []
    private var onUpdate: (@Sendable (TimedText) -> Void)?

    func startLive(inputFormat: AVAudioFormat, onUpdate: @escaping @Sendable (TimedText) -> Void) async throws {
        let locale = await Self.bestLocale()
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw EarsError.assetsUnavailable
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (stream, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)

        lock.lock()
        self.committed = []
        self.volatile = []
        self.onUpdate = onUpdate
        self.converter = BufferConverter(target: format)
        self.inputBuilder = builder
        self.analyzer = analyzer
        self.transcriber = transcriber
        lock.unlock()

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    self?.handle(result)
                }
            } catch {
                // The stream ends when analysis finishes or is cancelled.
            }
        }

        try await analyzer.start(inputSequence: stream)
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let converter = self.converter
        let builder = self.inputBuilder
        lock.unlock()
        guard let converter, let builder, let converted = converter.convert(buffer) else { return }
        builder.yield(AnalyzerInput(buffer: converted))
    }

    func finishLive() async -> TimedText {
        lock.lock()
        let builder = inputBuilder
        let analyzer = self.analyzer
        inputBuilder = nil
        lock.unlock()
        builder?.finish()
        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        await resultsTask?.value
        lock.lock()
        let text = TimedText(spans: committed + volatile).renumbered()
        self.analyzer = nil
        self.transcriber = nil
        self.converter = nil
        self.onUpdate = nil
        lock.unlock()
        return text
    }

    func transcribe(file url: URL) async throws -> TimedText {
        try await transcribeByReplaying(file: url)
    }

    // MARK: Results

    private func handle(_ result: SpeechTranscriber.Result) {
        let spans = Self.spans(from: result.text, isFinal: result.isFinal)
        lock.lock()
        if result.isFinal {
            committed.append(contentsOf: spans)
            volatile = []
        } else {
            volatile = spans
        }
        let text = TimedText(spans: committed + volatile).renumbered()
        let callback = onUpdate
        lock.unlock()
        callback?(text)
    }

    private static func spans(from text: AttributedString, isFinal: Bool) -> [TimedSpan] {
        var spans: [TimedSpan] = []
        for run in text.runs {
            let piece = String(text[run.range].characters)
            if piece.isEmpty { continue }
            var start: TimeInterval = 0
            var end: TimeInterval = 0
            if let range = run.audioTimeRange {
                start = range.start.seconds
                end = range.end.seconds
            }
            spans.append(TimedSpan(id: spans.count, text: piece, start: start, end: end, confidence: isFinal ? 1 : 0.5, isFinal: isFinal))
        }
        // Make sure every word ends with a separator so `plain` reads naturally.
        for i in spans.indices where !spans[i].text.last!.isWhitespace && i < spans.count - 1 {
            if !spans[i + 1].text.first!.isWhitespace && !spans[i + 1].text.first!.isPunctuation {
                spans[i].text += " "
            }
        }
        if let last = spans.indices.last, !spans[last].text.hasSuffix(" ") {
            spans[last].text += " "
        }
        return spans
    }

    private static func bestLocale() async -> Locale {
        let supported = await SpeechTranscriber.supportedLocales
        let current = Locale.current
        if let exact = supported.first(where: { $0.identifier(.bcp47) == current.identifier(.bcp47) }) { return exact }
        if let language = supported.first(where: { $0.language.languageCode == current.language.languageCode }) { return language }
        return supported.first ?? Locale(identifier: "en-US")
    }
}
