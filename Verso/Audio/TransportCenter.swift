import Foundation
import MediaPlayer
import Observation

/// Everything that represents Verso outside its own screens: the system
/// Now Playing card (lock screen, Control Center, CarPlay) and its remote
/// commands. It owns no state of its own — it mirrors the Reader and the
/// Player, and its commands call straight back into them.
///
/// Sync points are COARSE on purpose: play/pause flips, chapter changes,
/// and the Reader's permille facet (which itself only moves at sentence
/// scale). Between syncs the system extrapolates the elapsed time from
/// the playback rate, so nothing here ever runs per word.
@MainActor
final class TransportCenter {
    private unowned let engine: Engine
    private var started = false

    init(engine: Engine) {
        self.engine = engine
    }

    func start() {
        guard !started else { return }
        started = true
        setupRemoteCommands()
        track()
        sync()
    }

    // MARK: Observation

    private func track() {
        let reader = engine.reader
        let player = engine.player
        withObservationTracking {
            _ = reader.isSpeaking
            _ = reader.isPaused
            _ = reader.chapterIndex
            _ = reader.progressPermille
            _ = reader.document?.id
            _ = player.isPlaying
            _ = player.document?.id
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.sync()
                self.track()
            }
        }
    }

    private func sync() {
        let center = MPNowPlayingInfoCenter.default()
        if engine.reader.isSpeaking {
            center.nowPlayingInfo = readerInfo()
        } else if engine.player.isPlaying {
            center.nowPlayingInfo = playerInfo()
        } else {
            center.nowPlayingInfo = nil
        }
    }

    // MARK: Now Playing content

    /// The reader's position in seconds, on the same 2.6-words-per-second
    /// estimate the in-app readouts use: the system card and the book can
    /// never disagree about where the voice is.
    private func readerElapsed() -> (elapsed: Double, duration: Double) {
        let reader = engine.reader
        guard let document = reader.document else { return (0, 0) }
        let starts = document.chapterSpanStarts
        let total = starts.last ?? 0
        let chapter = min(max(reader.chapterIndex, 0), max(0, starts.count - 2))
        let global = (starts.indices.contains(chapter) ? starts[chapter] : 0) + (reader.currentIndex ?? 0)
        let wordsPerSecond = 2.6 * reader.rateMultiplier
        guard wordsPerSecond > 0 else { return (0, 0) }
        return (Double(global) / wordsPerSecond, Double(total) / wordsPerSecond)
    }

    private func readerInfo() -> [String: Any] {
        let reader = engine.reader
        guard let document = reader.document else { return [:] }
        let (elapsed, duration) = readerElapsed()
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: document.title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: reader.isPaused ? 0.0 : reader.rateMultiplier,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: reader.rateMultiplier,
            MPNowPlayingInfoPropertyChapterNumber: reader.chapterIndex + 1,
            MPNowPlayingInfoPropertyChapterCount: reader.chapters.count,
        ]
        if !document.author.isEmpty {
            info[MPMediaItemPropertyArtist] = document.author
        }
        let chapterTitle = reader.chapters.indices.contains(reader.chapterIndex)
            ? reader.chapters[reader.chapterIndex].title : ""
        info[MPMediaItemPropertyAlbumTitle] = chapterTitle.isEmpty
            ? "Chapter \(reader.chapterIndex + 1) of \(reader.chapters.count)"
            : "Chapter \(reader.chapterIndex + 1) · \(chapterTitle)"
        return info
    }

    private func playerInfo() -> [String: Any] {
        let player = engine.player
        guard let document = player.document else { return [:] }
        return [
            MPMediaItemPropertyTitle: document.title,
            MPMediaItemPropertyAlbumTitle: "Recording",
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime,
            MPMediaItemPropertyPlaybackDuration: player.duration,
            MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? Double(player.rate) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(player.rate),
        ]
    }

    // MARK: Remote commands

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.remotePlay() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.remotePause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.remoteToggle() }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.remoteSkip(15) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.remoteSkip(-15) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self.remoteSeek(to: position) }
            return .success
        }
    }

    /// The reader wins ties: it is the only one of the two that can be
    /// mid-session while the other merely holds a loaded document.
    private var readerIsLive: Bool { engine.reader.isSpeaking }

    private func remotePlay() {
        if readerIsLive {
            engine.reader.resume()
        } else if engine.player.document != nil {
            engine.player.play()
        }
    }

    private func remotePause() {
        if readerIsLive {
            engine.reader.pause()
        } else if engine.player.isPlaying {
            engine.player.pause()
        }
    }

    private func remoteToggle() {
        if readerIsLive {
            engine.reader.toggle()
        } else if engine.player.document != nil {
            engine.player.toggle()
        }
    }

    private func remoteSkip(_ seconds: TimeInterval) {
        if readerIsLive {
            engine.reader.skip(seconds)
        } else if engine.player.document != nil {
            engine.player.skip(seconds)
        }
    }

    private func remoteSeek(to position: Double) {
        if readerIsLive {
            // The reader seeks in words; go through its own ±skip math so
            // chapter crossings land exactly like an in-app skip.
            let (elapsed, _) = readerElapsed()
            engine.reader.skip(position - elapsed)
        } else if engine.player.document != nil {
            engine.player.seek(to: position)
        }
    }
}
