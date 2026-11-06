import Foundation
import AVFoundation
import FluidAudio
import Observation

/// The on-device neural reading voice: Kokoro-82M, run by FluidAudio's
/// Kokoro ANE pipeline (Core ML). The models download once (~150 MB) into
/// the app's own container; after that, synthesis is fully offline.
///
/// This type owns the model lifecycle (download / load / synthesize). The
/// sentence-at-a-time playback lives in `KokoroPlayer` below; `Reader`
/// conducts both, the same way it conducts the Apple synthesizer.
///
/// The manager underneath is a FluidAudio actor, so model loads and
/// synthesis already run off the main actor; this class only holds the
/// observable state and awaits it.
@MainActor
@Observable
final class KokoroVoice {
    static let shared = KokoroVoice()

    enum ModelState: Equatable {
        case notDownloaded
        case downloading
        case ready
        case failed(String)
    }

    private(set) var modelState: ModelState = .notDownloaded

    /// Whether the models are on disk, computed ONCE off the main actor at
    /// launch (and refreshed at explicit checkpoints). The old check walked
    /// the model directory on the main actor on every `Reader.play`.
    private(set) var modelsPresent = false

    /// The Kokoro English voices Verso offers, defaults first.
    static let englishVoices: [(id: String, name: String, detail: String)] = [
        ("af_heart", "Heart", "American · female · Kokoro's default"),
        ("af_bella", "Bella", "American · female"),
        ("af_sarah", "Sarah", "American · female"),
        ("af_nicole", "Nicole", "American · female"),
        ("af_sky", "Sky", "American · female"),
        ("am_michael", "Michael", "American · male"),
        ("am_adam", "Adam", "American · male"),
        ("am_puck", "Puck", "American · male"),
        ("bf_emma", "Emma", "British · female"),
        ("bf_isabella", "Isabella", "British · female"),
        ("bm_george", "George", "British · male"),
        ("bm_lewis", "Lewis", "British · male"),
    ]
    static let defaultVoiceID = "af_heart"
    static let sampleRate = 24_000

    /// Where the models live: inside the app container, under a root we
    /// choose, so "downloaded or not" is a question disk can answer.
    nonisolated static var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("KokoroANE", isDirectory: true)
    }

    /// True once the one-time model download has landed. The SDK pins its
    /// assets under `<root>/kokoro-82m-coreml/…`; real content there means
    /// the download happened. This walks the directory — call it off the
    /// main actor (see `checkModelsOnDisk`), never per play.
    nonisolated static var modelsDownloaded: Bool {
        let dir = modelsDirectory.appendingPathComponent("kokoro-82m-coreml")
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return false
        }
        var total = 0
        for case let url as URL in enumerator {
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            if total > 20_000_000 { return true }
        }
        return false
    }

    /// The disk walk, awaited off the main actor.
    static func checkModelsOnDisk() async -> Bool {
        await Task.detached(priority: .utility) { modelsDownloaded }.value
    }

    private var manager: KokoroAneManager?
    private var prepared = false

    private init() {
        Task {
            modelsPresent = await Self.checkModelsOnDisk()
        }
    }

    private func makeManager() -> KokoroAneManager {
        if let manager { return manager }
        let created = KokoroAneManager(
            variant: .english,
            defaultVoice: Self.defaultVoiceID,
            directory: Self.modelsDirectory,
            version: .v3
        )
        manager = created
        return created
    }

    /// Syncs the shown state with what's on disk (Settings appearing).
    func refreshState() {
        guard modelState != .downloading else { return }
        modelState = modelsPresent ? .ready : .notDownloaded
        Task {
            let present = await Self.checkModelsOnDisk()
            modelsPresent = present
            if modelState != .downloading {
                modelState = present ? .ready : .notDownloaded
            }
        }
    }

    /// The Settings "Download" action: fetch the models and the chosen
    /// voice pack, then load the pipeline. The SDK exposes no progress
    /// callback, so the state stays `.downloading` until this returns.
    func downloadModels(voice: String) async {
        guard modelState != .downloading else { return }
        modelState = .downloading
        do {
            try await makeManager().initialize(preloadVoices: [voice])
            prepared = true
            modelsPresent = true
            modelState = .ready
        } catch {
            modelState = .failed(error.localizedDescription)
        }
    }

    /// Fetches one more voice pack (packs download per voice) once the
    /// models exist. Synthesis would fetch it lazily too, but only with a
    /// network; doing it at selection time keeps playback from stalling.
    func preload(voice: String) async {
        guard modelsPresent else { return }
        try? await makeManager().initialize(preloadVoices: [voice])
    }

    /// Loads the pipeline when the models are on disk. False means the
    /// caller should stay on the Apple voice path.
    func prepareIfDownloaded(voice: String) async -> Bool {
        if prepared { return true }
        if !modelsPresent {
            modelsPresent = await Self.checkModelsOnDisk()
            guard modelsPresent else { return false }
        }
        do {
            try await makeManager().initialize(preloadVoices: [voice])
            prepared = true
            modelState = .ready
            return true
        } catch {
            modelState = .failed(error.localizedDescription)
            return false
        }
    }

    /// One sentence of speech: 24 kHz mono Float32 PCM.
    func synthesize(text: String, voice: String, speed: Float) async throws -> [Float] {
        let result = try await makeManager().synthesizeDetailed(text: text, voice: voice, speed: speed)
        return result.samples
    }
}

/// Plays Kokoro sentences through an `AVAudioEngine`. One long-lived
/// instance serves every play session: the engine stays attached and warm,
/// up to two buffers stay scheduled on the node so sentence N+1 is already
/// queued while N plays (no inter-sentence gap), and the word clock reads
/// the node's own sample time — pausing freezes that clock, so no Date
/// bookkeeping is needed and the highlight cannot drift.
///
/// Word timing inside a sentence is estimated: the sentence's measured
/// duration is spread across its words in proportion to their length.
@MainActor
final class KokoroPlayer {
    struct Chunk {
        var text: String
        var spanStart: Int
        var wordWeights: [Int]
    }

    var onWord: ((Int) -> Void)?
    var onQueueFinished: (() -> Void)?
    var onError: ((Error) -> Void)?

    private(set) var isActive = false
    private(set) var isPaused = false

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var configured = false
    private let format = AVAudioFormat(standardFormatWithSampleRate: Double(KokoroVoice.sampleRate), channels: 1)!

    private var generation = 0
    private var runTask: Task<Void, Never>?

    /// One scheduled buffer on the node's timeline.
    private struct Scheduled {
        var startSample: Int64
        var duration: TimeInterval
        var spanStart: Int
        /// Start offset (seconds into the chunk) of each word.
        var wordOffsets: [TimeInterval]
    }
    private var timeline: [Scheduled] = []
    private var timelineCursor = 0
    private var nextStartSample: Int64 = 0
    private var inFlight = 0
    private var totalScheduled = 0
    private var totalPlayed = 0
    private var schedulingDone = false
    private var slotWaiters: [CheckedContinuation<Void, Never>] = []

    private var wordTimer: Timer?
    private var lastReportedSpan: Int?

    // MARK: Control

    func start(chunks: [Chunk], synthesize: @escaping (String) async throws -> [Float]) {
        stop()
        let gen = generation
        isActive = true
        isPaused = false
        startEngineIfNeeded()
        node.play()
        runTask = Task { [weak self] in
            await self?.run(chunks: chunks, gen: gen, synthesize: synthesize)
        }
        startWordTimer(gen: gen)
    }

    func pause() {
        guard isActive, !isPaused else { return }
        isPaused = true
        node.pause()
    }

    func resume() {
        guard isActive, isPaused else { return }
        isPaused = false
        startEngineIfNeeded()
        node.play()
    }

    func stop() {
        generation += 1
        runTask?.cancel()
        runTask = nil
        node.stop()
        stopWordTimer()
        timeline = []
        timelineCursor = 0
        nextStartSample = 0
        inFlight = 0
        totalScheduled = 0
        totalPlayed = 0
        schedulingDone = false
        let waiters = slotWaiters
        slotWaiters = []
        waiters.forEach { $0.resume() }
        isActive = false
        isPaused = false
        lastReportedSpan = nil
    }

    // MARK: The queue

    private func run(chunks: [Chunk], gen: Int, synthesize: @escaping (String) async throws -> [Float]) async {
        var prefetch: Task<[Float], Error>?
        func launch(_ i: Int) -> Task<[Float], Error>? {
            guard chunks.indices.contains(i) else { return nil }
            let text = chunks[i].text
            return Task { try await synthesize(text) }
        }
        prefetch = launch(0)
        var index = 0
        while index < chunks.count {
            guard gen == generation, !Task.isCancelled else { return }
            // Keep at most two buffers on the node: the next sentence is
            // scheduled before the current one ends, but synthesis never
            // races a whole chapter ahead of the listener.
            while inFlight >= 2 {
                await withCheckedContinuation { slotWaiters.append($0) }
                guard gen == generation, !Task.isCancelled else { return }
            }
            let samples: [Float]
            do {
                guard let current = prefetch else { return }
                samples = try await current.value
            } catch {
                if gen == generation {
                    // Cut any scheduled Kokoro audio before the caller
                    // hands the book to the Apple voice, or they'd overlap.
                    node.stop()
                    isActive = false
                    onError?(error)
                }
                return
            }
            prefetch = nil
            guard gen == generation, !Task.isCancelled else { return }
            if !samples.isEmpty {
                schedule(samples: samples, chunk: chunks[index], gen: gen)
            }
            index += 1
            if index < chunks.count { prefetch = launch(index) }
        }
        schedulingDone = true
        maybeFinish(gen: gen)
    }

    private func schedule(samples: [Float], chunk: Chunk, gen: Int) {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { source in
                if let base = source.baseAddress {
                    channel.update(from: base, count: samples.count)
                }
            }
        }

        let duration = Double(samples.count) / format.sampleRate
        let totalWeight = max(1, chunk.wordWeights.reduce(0, +))
        var wordOffsets: [TimeInterval] = []
        wordOffsets.reserveCapacity(chunk.wordWeights.count)
        var at: TimeInterval = 0
        for weight in chunk.wordWeights {
            wordOffsets.append(at)
            at += duration * Double(max(1, weight)) / Double(totalWeight)
        }

        // Anchor the first buffer at the node's current position; later
        // buffers chain onto the previous one's end. If synthesis fell
        // behind the playhead, start at the playhead instead of the past.
        let anchor = currentSampleTime()
        if timeline.isEmpty { nextStartSample = anchor }
        let startSample = max(nextStartSample, anchor)
        nextStartSample = startSample + Int64(samples.count)
        timeline.append(Scheduled(startSample: startSample, duration: duration, spanStart: chunk.spanStart, wordOffsets: wordOffsets))
        inFlight += 1
        totalScheduled += 1
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] in
            Task { @MainActor in self?.noteBufferPlayed(gen: gen) }
        }
    }

    private func noteBufferPlayed(gen: Int) {
        guard gen == generation else { return }
        inFlight = max(0, inFlight - 1)
        totalPlayed += 1
        if !slotWaiters.isEmpty {
            slotWaiters.removeFirst().resume()
        }
        maybeFinish(gen: gen)
    }

    private func maybeFinish(gen: Int) {
        guard gen == generation, schedulingDone, totalPlayed >= totalScheduled, isActive else { return }
        isActive = false
        stopWordTimer()
        onQueueFinished?()
    }

    // MARK: Word clock (node sample time — freezes on pause, cannot drift)

    private func currentSampleTime() -> Int64 {
        guard let renderTime = node.lastRenderTime, renderTime.isSampleTimeValid,
              let playerTime = node.playerTime(forNodeTime: renderTime), playerTime.isSampleTimeValid else {
            return nextStartSample
        }
        return playerTime.sampleTime
    }

    private func startWordTimer(gen: Int) {
        stopWordTimer()
        wordTimer = Timer.commonScheduled(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(gen: gen) }
        }
    }

    private func stopWordTimer() {
        wordTimer?.invalidate()
        wordTimer = nil
    }

    private func tick(gen: Int) {
        guard gen == generation, isActive, !timeline.isEmpty else { return }
        let now = Double(currentSampleTime()) / format.sampleRate
        while timelineCursor + 1 < timeline.count,
              Double(timeline[timelineCursor + 1].startSample) / format.sampleRate <= now {
            timelineCursor += 1
        }
        // Prune far-behind chunks so the scan stays O(1) over a long chapter.
        if timelineCursor > 64 {
            timeline.removeFirst(32)
            timelineCursor -= 32
        }
        let entry = timeline[timelineCursor]
        let start = Double(entry.startSample) / format.sampleRate
        guard now >= start else { return }
        let local = now - start
        var current = entry.spanStart
        if local <= entry.duration {
            for (i, offset) in entry.wordOffsets.enumerated() where offset <= local {
                current = entry.spanStart + i
            }
        } else if let last = entry.wordOffsets.indices.last {
            // Between buffers (or past the end): the last word stands.
            current = entry.spanStart + last
        }
        if current != lastReportedSpan {
            lastReportedSpan = current
            onWord?(current)
        }
    }

    private func startEngineIfNeeded() {
        if !configured {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            configured = true
        }
        if !engine.isRunning {
            engine.prepare()
            try? engine.start()
        }
    }
}
