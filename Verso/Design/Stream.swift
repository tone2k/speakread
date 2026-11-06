import SwiftUI

// The bit-stream layer: readouts of the real data moving underneath.
// Nothing here is decoration. Every number is a value the engines hold.

/// `0x002A3F00`: a count as a fixed-width hex word.
func formatHex(_ value: Int, digits: Int = 8) -> String {
    let s = String(max(0, value), radix: 16, uppercase: true)
    return "0x" + String(repeating: "0", count: max(0, digits - s.count)) + s
}

/// `00412`: a span index as a fixed-width decimal.
func formatIndex(_ value: Int, digits: Int = 5) -> String {
    let s = String(max(0, value))
    return String(repeating: "0", count: max(0, digits - s.count)) + s
}

/// A horizontal line through the middle of its frame, for dashed strokes.
struct HLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// A page turn as a buffer flush: the new content is revealed from the
/// leading edge. Pair with `.animation(.linear(duration: 0.18), value:)`.
struct FlushModifier: ViewModifier {
    var reveal: CGFloat

    func body(content: Content) -> some View {
        content.mask(alignment: .leading) {
            Rectangle().scaleEffect(x: max(0.001, reveal), y: 1, anchor: .leading)
        }
    }
}

extension AnyTransition {
    static var flush: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: FlushModifier(reveal: 0), identity: FlushModifier(reveal: 1)),
            removal: .opacity
        )
    }
}

/// A data line: fields separated by dots, in label type, under a hairline.
struct StreamLine: View {
    let fields: [String]
    var live = false

    var body: some View {
        HStack(spacing: 8) {
            if live { BlinkDot(size: 6) }
            Text(fields.joined(separator: " · "))
                .hudText(.label)
                .foregroundStyle(HUD.fg1)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .frame(height: 24)
        .overlay(alignment: .top) { Rectangle().fill(HUD.rule).frame(height: 1) }
    }
}

/// The level as eight bits: `level * 255`, one square per bit, high bit first.
struct BitMeter: View {
    let level: Float
    var size: CGFloat = 6

    var body: some View {
        let value = Int(min(max(level, 0), 1) * 255)
        HStack(spacing: 2) {
            ForEach((0..<8).reversed(), id: \.self) { bit in
                Rectangle()
                    .fill(value & (1 << bit) != 0 ? HUD.signal : HUD.rule)
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The write head at the end of a live transcript: a blinking block and the
/// lag between the microphone and the last committed word. A leaf: it is
/// the only view in the transcript that reads the clock, so the transcript
/// itself never re-runs at the data rate.
struct RecorderWriteHead: View {
    let recorder: Recorder

    var body: some View {
        if !recorder.isPaused {
            let committed = recorder.finalText.spans.last?.end ?? recorder.elapsed
            let lag = max(0, recorder.elapsed - committed)
            HStack(spacing: 8) {
                BlinkDot(size: 10)
                Text("WRITE HEAD · +\(String(format: "%.1f", lag))S")
                    .hudText(.label)
                    .foregroundStyle(HUD.signalInk)
            }
            .padding(.top, 6)
        }
    }
}

// MARK: - Leaf stream lines (each reads only the fast values it shows)

struct RecorderStreamLine: View {
    let recorder: Recorder

    var body: some View {
        HStack(spacing: 12) {
            StreamLine(fields: [
                recorder.isPaused ? "HOLD" : "REC",
                "\(Int(recorder.sampleRate))HZ 1CH",
                "SMP \(formatHex(recorder.sampleCount))",
                "T+\(formatTimecode(recorder.elapsed, tenths: true))",
                "W \(formatIndex(recorder.finalText.spans.count))"
            ], live: !recorder.isPaused)
            BitMeter(level: recorder.level)
                .padding(.top, 1)
        }
    }
}

struct ReaderStreamLine: View {
    let reader: Reader

    var body: some View {
        let current = reader.currentIndex ?? 0
        let buffered = max(0, (reader.bufferedThrough ?? current) - current)
        let engine = reader.voiceEngine == .kokoro ? "KOKORO \(reader.kokoroVoiceID)" : "APPLE \((reader.voice?.name ?? "").uppercased())"
        StreamLine(fields: [
            reader.isSpeaking && !reader.isPaused ? "RD" : "IDLE",
            "CH \(String(format: "%02d", reader.chapterIndex + 1))",
            "SPAN \(formatIndex(current))/\(formatIndex(reader.text.spans.count))",
            "BUF +\(buffered)W",
            engine
        ], live: reader.isSpeaking && !reader.isPaused)
    }
}

struct PlayerStreamLine: View {
    let player: Player

    var body: some View {
        StreamLine(fields: [
            player.isPlaying ? "PLAY" : "HOLD",
            "\(Int(player.sampleRate))HZ",
            "SMP \(formatHex(Int(player.currentTime * player.sampleRate)))",
            "T \(formatTimecode(player.currentTime, tenths: true))/\(formatTimecode(player.duration))",
            "SPAN \(formatIndex(player.currentIndex ?? 0))"
        ], live: player.isPlaying)
    }
}

// MARK: - RAW: the transcript as packets

/// The timed text as it is stored: one row per word, with its time range.
/// Tap a row to seek. This is the data model shown without dressing.
struct PacketListView: View {
    let text: TimedText
    let currentIndex: Int?
    var onTap: ((Int) -> Void)?

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        Text("IDX").frame(width: 48, alignment: .leading)
                        Text("START").frame(width: 84, alignment: .leading)
                        Text("END").frame(width: 84, alignment: .leading)
                        Text("C").frame(width: 24, alignment: .leading)
                        Text("WORD")
                    }
                    .hudText(.label)
                    .foregroundStyle(HUD.fg2)
                    .frame(height: 24)
                    ForEach(text.spans) { span in
                        let live = span.id == currentIndex
                        Button {
                            onTap?(span.id)
                        } label: {
                            HStack(spacing: 12) {
                                Text(formatIndex(span.id)).frame(width: 48, alignment: .leading)
                                Text(Self.stamp(span.start)).frame(width: 84, alignment: .leading)
                                Text(Self.stamp(span.end)).frame(width: 84, alignment: .leading)
                                Text(String(format: "%02X", Int(min(max(span.confidence, 0), 1) * 255))).frame(width: 24, alignment: .leading)
                                Text(span.text.trimmingCharacters(in: .whitespacesAndNewlines))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .hudText(.meta)
                            .foregroundStyle(live ? HUD.onSignal : (span.isFinal ? HUD.fg0 : HUD.fg2))
                            .padding(.horizontal, 4)
                            .frame(height: 22)
                            .background(live ? HUD.signal : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(span.id)
                    }
                }
            }
            .onChange(of: currentIndex) { _, new in
                if let new, new % 12 == 0 { scroller.scrollTo(new, anchor: .center) }
            }
        }
    }

    private static func stamp(_ t: TimeInterval) -> String {
        let s = max(0, t)
        let m = Int(s) / 60
        let sec = s - Double(m * 60)
        return String(format: "%02d:%06.3f", m, sec)
    }
}
