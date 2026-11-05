import AVFoundation

/// One audio session for the whole app. Recording and playback share it.
enum AudioSession {
    enum Mode {
        case record
        case play
    }

    static func configure(_ mode: Mode) throws {
        let session = AVAudioSession.sharedInstance()
        switch mode {
        case .record:
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers])
        case .play:
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
        }
        try session.setActive(true, options: [])
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
