import Foundation
import AVFoundation
import Observation

/// Plays a recording back. Tap a word in the transcript and the player goes there.
@MainActor
@Observable
final class Player: NSObject, AVAudioPlayerDelegate {
    private(set) var document: Document?
    private(set) var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var currentIndex: Int?
    var transcript = TimedText()
    var rate: Float = 1.0 {
        didSet { player?.rate = rate }
    }

    private var player: AVAudioPlayer?
    private var ticker: Timer?

    func load(_ document: Document) {
        stop()
        self.document = document
        transcript = document.transcript
        guard let name = document.audioFileName else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: AudioStore.url(for: name))
            p.enableRate = true
            p.rate = rate
            p.delegate = self
            p.prepareToPlay()
            player = p
            duration = p.duration
            let start = transcript.spans.indices.contains(document.spanIndex) ? transcript.spans[document.spanIndex].start : 0
            p.currentTime = start
            currentTime = start
            currentIndex = transcript.index(at: start)
        } catch {
            player = nil
        }
    }

    func play() {
        guard let player else { return }
        try? AudioSession.configure(.play)
        player.play()
        isPlaying = true
        ticker?.invalidate()
        ticker = Timer.commonScheduled(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        ticker?.invalidate()
        ticker = nil
        save()
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func stop() {
        pause()
        player?.stop()
        player = nil
        document = nil
        currentIndex = nil
        currentTime = 0
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = max(0, min(time, player.duration))
        currentTime = player.currentTime
        currentIndex = transcript.index(at: currentTime)
        save()
    }

    func seek(toSpan index: Int) {
        guard transcript.spans.indices.contains(index) else { return }
        seek(to: transcript.spans[index].start)
    }

    func skip(_ seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    private func tick() {
        guard let player, isPlaying else { return }
        currentTime = player.currentTime
        let index = transcript.index(at: currentTime)
        if index != currentIndex {
            currentIndex = index
        }
    }

    private func save() {
        guard let document else { return }
        if let currentIndex { document.spanIndex = currentIndex }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.ticker?.invalidate()
            self.ticker = nil
            self.save()
        }
    }
}
