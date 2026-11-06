import SwiftUI

/// The follow-me transport: one strip pinned under every screen while a
/// recording or a playback is live, gone the moment neither is. It reads
/// ONLY the same owners the screens read — Engine's recorder, reader and
/// player — and its buttons call the same methods the screens' buttons
/// call, so the strip can never disagree with the surface it floats over.
///
/// Recording wins ties: it is the only session that cannot be restarted
/// if it is lost. Fast values live in leaf views (`StripClock`,
/// `RecorderScope`), so the strip's body never re-runs at data rate.
struct TransportStrip: View {
    @Environment(Engine.self) private var engine

    var body: some View {
        if engine.recorder.isRecording {
            RecordingStrip(recorder: engine.recorder)
        } else if engine.reader.isSpeaking {
            ReaderStrip(reader: engine.reader)
        } else if engine.player.isPlaying, engine.player.document != nil {
            PlayerStrip(player: engine.player)
        }
    }

    /// The shared chrome: 2 pt signal line over a bg1 band.
    static func chrome<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(HUD.signal).frame(height: 2)
            content()
                .frame(height: 50)
                .padding(.horizontal, 12)
        }
        .background(HUD.bg1)
        .overlay(alignment: .bottom) { Rectangle().fill(HUD.rule).frame(height: 1) }
    }
}

// MARK: Recording

private struct RecordingStrip: View {
    @Environment(Engine.self) private var engine
    let recorder: Recorder

    var body: some View {
        TransportStrip.chrome {
            HStack(spacing: 10) {
                Button {
                    if engine.path.last != .recording { engine.path.append(.recording) }
                } label: {
                    HStack(spacing: 8) {
                        if recorder.isPaused {
                            Rectangle().fill(HUD.fg1).frame(width: 8, height: 8)
                        } else {
                            BlinkDot()
                        }
                        Text(recorder.isPaused ? "PAUSED" : "REC")
                            .hudText(.label)
                            .foregroundStyle(recorder.isPaused ? HUD.fg1 : HUD.fg0)
                        StripClock(recorder: recorder)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(recorder.isPaused ? "Recording paused. Go to the recording screen." : "Recording. Go to the recording screen.")

                RecorderScope(recorder: recorder, height: 22)
                    .frame(width: 56)

                Spacer(minLength: 4)

                Button { recorder.mark() } label: { Text("⚑") }
                    .buttonStyle(HUDButtonStyle(size: 44))
                    .accessibilityLabel("Drop a mark")
                Button {
                    if recorder.isPaused { recorder.resume() } else { recorder.pause() }
                } label: {
                    Text(recorder.isPaused ? "▶" : "❚❚")
                }
                .buttonStyle(HUDButtonStyle(size: 44))
                .accessibilityLabel(recorder.isPaused ? "Resume recording" : "Pause recording")
                Button {
                    Task { await engine.stopRecording() }
                } label: {
                    Text("■").hudText(.title3)
                }
                .buttonStyle(SignalButtonStyle(size: 44))
                .accessibilityLabel("Stop recording")
            }
        }
    }
}

/// The recording clock as a leaf: Recorder's 20 Hz elapsed republishes
/// re-run this one small view, exactly like `RecorderTimecode` on the
/// recording screen.
private struct StripClock: View {
    let recorder: Recorder

    var body: some View {
        Text(formatTimecode(recorder.elapsed))
            .hudText(.meta)
            .foregroundStyle(HUD.fg0)
    }
}

// MARK: Reading (book playback)

private struct ReaderStrip: View {
    @Environment(Engine.self) private var engine
    let reader: Reader

    var body: some View {
        TransportStrip.chrome {
            HStack(spacing: 10) {
                Button {
                    if let document = reader.document, engine.path.last != .reading(document.id) {
                        engine.path.append(.reading(document.id))
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reader.document?.title ?? "")
                            .hudText(.meta)
                            .foregroundStyle(HUD.fg0)
                            .lineLimit(1)
                        Text(metaLine)
                            .hudText(.micro)
                            .foregroundStyle(HUD.fg1)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Now reading \(reader.document?.title ?? ""). Go to the book.")

                CellBar(progress: Double(reader.progressPermille) / 1000, cells: 20)
                    .frame(width: 64)

                Spacer(minLength: 4)

                Button {
                    reader.toggle()
                } label: {
                    Image(systemName: reader.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 16))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(HUDButtonStyle(size: 44, primary: true))
                .accessibilityLabel(reader.isPaused ? "Resume reading" : "Pause reading")
                Button {
                    reader.stop()
                    if engine.activity != .none { engine.activity = .none }
                } label: {
                    Text("■").hudText(.title3)
                }
                .buttonStyle(HUDButtonStyle(size: 44))
                .accessibilityLabel("Stop reading")
            }
        }
    }

    private var metaLine: String {
        var parts = ["CH \(String(format: "%02d", reader.chapterIndex + 1))"]
        // 0% means nothing — no percent readout until there is progress.
        if reader.progressPermille >= 10 {
            parts.append("\(reader.progressPermille / 10)%")
        }
        if reader.minutesLeft > 0 {
            parts.append("~\(reader.minutesLeft) MIN LEFT")
        }
        if reader.isPaused { parts.append("PAUSED") }
        return parts.joined(separator: " · ")
    }
}

// MARK: Player (recording playback)

private struct PlayerStrip: View {
    @Environment(Engine.self) private var engine
    let player: Player

    var body: some View {
        TransportStrip.chrome {
            HStack(spacing: 10) {
                Button {
                    if let document = player.document, engine.path.last != .playback(document.id) {
                        engine.path.append(.playback(document.id))
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.document?.title ?? "")
                            .hudText(.meta)
                            .foregroundStyle(HUD.fg0)
                            .lineLimit(1)
                        Text("T \(formatTimecode(player.currentTime)) / \(formatTimecode(player.duration))")
                            .hudText(.micro)
                            .foregroundStyle(HUD.fg1)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Playing \(player.document?.title ?? ""). Go to the recording.")

                Spacer(minLength: 4)

                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(HUDButtonStyle(size: 44, primary: true))
                .accessibilityLabel(player.isPlaying ? "Pause playback" : "Play")
                Button {
                    player.stop()
                } label: {
                    Text("■").hudText(.title3)
                }
                .buttonStyle(HUDButtonStyle(size: 44))
                .accessibilityLabel("Stop playback")
            }
        }
    }
}
