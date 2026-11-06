import SwiftUI

/// Listening to a book on the closed phone: a window of the chapter
/// around the spoken word, the lock on the current word, transport under
/// the thumb. The window snaps to sentence starts and moves in steps
/// (P13) instead of sliding a word at a time.
struct ListeningView: View {
    @Environment(Engine.self) private var engine
    let document: Document
    var fontSize: CGFloat = 19

    @State private var windowStart = 0
    @State private var sentenceStarts: [Int] = [0]

    private var reader: Reader { engine.reader }
    private static let windowSize = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                CartridgeMini(progress: document.progress)
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.title)
                        .hudText(.title3)
                        .foregroundStyle(HUD.fg0)
                        .lineLimit(1)
                    Text(subtitle)
                        .hudText(.meta)
                        .foregroundStyle(HUD.fg1)
                        .lineLimit(1)
                }
                Spacer()
            }

            if reader.isDialogue {
                SpeakerKicker(name: speakerName ?? "Narrator")
                    .padding(.top, 18)
                    .animation(.snappy, value: reader.currentSpeaker)
            }

            ScrollView {
                WordRun(
                    spans: window,
                    currentIndex: reader.currentIndex,
                    fontSize: fontSize + 5,
                    dimBefore: true,
                    onTap: { reader.play(from: $0) }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, reader.isDialogue ? 12 : 24)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)

            ListeningProgress(document: document)
                .padding(.top, 4)

            HStack(spacing: 28) {
                Spacer()
                Button { reader.skipTurn(-1) } label: { Text(reader.isDialogue ? "‹ LINE" : "−15") }
                    .buttonStyle(HUDButtonStyle(size: 56))
                    .accessibilityLabel(reader.isDialogue ? "Previous line" : "Back 15 seconds")
                Button {
                    if !reader.isSpeaking || reader.isPaused { engine.playReading(document) } else { reader.pause() }
                } label: {
                    Image(systemName: reader.isSpeaking && !reader.isPaused ? "pause.fill" : "play.fill")
                        .font(.system(size: 26))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(HUDButtonStyle(size: 84, primary: true))
                .accessibilityLabel(reader.isSpeaking && !reader.isPaused ? "Pause" : "Play")
                Button { reader.skipTurn(1) } label: { Text(reader.isDialogue ? "LINE ›" : "+15") }
                    .buttonStyle(HUDButtonStyle(size: 56))
                    .accessibilityLabel(reader.isDialogue ? "Next line" : "Forward 15 seconds")
                Spacer()
            }
            .padding(.top, 16)

            HStack {
                RateMenu()
                Spacer()
                Text("VOICE · \((reader.voice?.name ?? "—").uppercased())")
                    .hudText(.meta)
                    .foregroundStyle(HUD.fg1)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 12)
                    .overlay(Rectangle().strokeBorder(HUD.rule, lineWidth: 1))
                Spacer()
                HoldToNoteButton()
            }
            .padding(.top, 18)
        }
        .padding(.horizontal, HUD.Space.closedMargin)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .onAppear { rebuildSentenceStarts() }
        .onChange(of: reader.chapterIndex) {
            windowStart = 0
            rebuildSentenceStarts()
        }
        .onChange(of: reader.currentIndex) { adjustWindow() }
    }

    private var window: ArraySlice<TimedSpan> {
        let spans = reader.text.spans
        guard !spans.isEmpty else { return spans[...] }
        let start = min(windowStart, spans.count - 1)
        let end = min(spans.count, start + Self.windowSize)
        return spans[start..<end]
    }

    private func rebuildSentenceStarts() {
        let ends = reader.text.sentenceEnds()
        sentenceStarts = [0] + ends.map { $0 + 1 }.filter { $0 < reader.text.spans.count }
    }

    /// Snap the window so the current word sits a few words into a
    /// sentence; move only when it passes two-thirds of the window or
    /// jumps outside it entirely.
    private func adjustWindow() {
        let spans = reader.text.spans
        guard !spans.isEmpty, let current = reader.currentIndex else { return }
        let limit = windowStart + (Self.windowSize * 2) / 3
        guard current > limit || current < windowStart else { return }
        let target = max(0, current - 8)
        let snapped = sentenceStarts.last { $0 <= target } ?? 0
        if snapped != windowStart { windowStart = snapped }
    }

    private var speakerName: String? {
        guard let speaker = reader.currentSpeaker else { return nil }
        return reader.member(for: speaker)?.name ?? Cast.displayName(speaker)
    }

    private var subtitle: String {
        let chapter = reader.chapters.indices.contains(reader.chapterIndex) ? reader.chapters[reader.chapterIndex].title : ""
        let chapterLabel = "CH \(String(format: "%02d", reader.chapterIndex + 1))"
        return document.author.isEmpty ? chapterLabel : "\(document.author.uppercased()) · \(chapterLabel)"
    }
}

/// Timeline + readouts as a leaf: the word clock re-runs this view only.
struct ListeningProgress: View {
    @Environment(Engine.self) private var engine
    let document: Document

    private var reader: Reader { engine.reader }

    var body: some View {
        let count = max(1, reader.text.spans.count)
        let current = reader.currentIndex ?? 0
        VStack(spacing: 2) {
            HUDTimeline(progress: Double(current) / Double(count)) { fraction in
                reader.play(from: Int(fraction * Double(count - 1)))
            }
            HStack {
                Text("~\(formatTimecode(elapsedEstimate))")
                Spacer()
                Text("~\(minutesInChapter) MIN IN CH")
                Spacer()
                Text("~\(formatTimecode(totalEstimate))")
            }
            .hudText(.meta)
            .foregroundStyle(HUD.fg1)
        }
    }

    private var minutesInChapter: Int {
        Int(ceil(max(0, reader.secondsLeftInChapter) / 60))
    }

    private var elapsedEstimate: TimeInterval {
        Double(reader.currentIndex ?? 0) / (2.6 * reader.rateMultiplier)
    }

    private var totalEstimate: TimeInterval {
        Double(reader.text.spans.count) / (2.6 * reader.rateMultiplier)
    }
}
