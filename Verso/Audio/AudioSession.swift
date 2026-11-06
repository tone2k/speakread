import AVFoundation

/// One audio session for the whole app. Recording and playback share it.
/// Reconfiguring the session (setCategory + setActive) costs tens to hundreds
/// of milliseconds, so the mode is cached: configuring for the mode already in
/// effect only re-asserts activation, which is cheap enough to do on a tap.
enum AudioSession {
    enum Mode {
        case record
        case play
    }

    private static let lock = NSLock()
    private static var activeMode: Mode?

    static func configure(_ mode: Mode) throws {
        lock.lock()
        defer { lock.unlock() }
        let session = AVAudioSession.sharedInstance()
        if activeMode == mode {
            try session.setActive(true, options: [])
            return
        }
        switch mode {
        case .record:
            // One session shape for the whole reading/recording surface:
            // the Reader plays through this same configuration, so a
            // hold-to-note during reading never reconfigures the session
            // (a category switch costs hundreds of ms and eats words).
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers])
        case .play:
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
        }
        try session.setActive(true, options: [])
        activeMode = mode
    }

    /// Configures off the caller's thread, for warming the session up ahead of
    /// the tap that will need it (opening a book, showing a screen).
    static func configureAsync(_ mode: Mode) {
        Task.detached(priority: .userInitiated) { try? configure(mode) }
    }

    static func deactivate() {
        lock.lock()
        activeMode = nil
        lock.unlock()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

extension Timer {
    /// A timer that keeps firing while the UI is tracking (scroll view
    /// scrolling runs the run loop in `.tracking`, where `.default`-mode
    /// timers freeze — the old word clocks stalled on every scroll).
    static func commonScheduled(withTimeInterval interval: TimeInterval, repeats: Bool, block: @escaping (Timer) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats, block: block)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
