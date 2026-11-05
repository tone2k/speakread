import SwiftUI

/// Listening to a book on the closed phone: the sentence being read, large,
/// with the ribbon under the spoken word.
struct ListeningView: View {
    @Environment(Engine.self) private var engine
    let document: Document
    var fontSize: CGFloat = 19

    private var reader: Reader { engine.reader }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                CoverThumb(title: document.title, progress: document.progress)
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.title).font(Theme.serif(18)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(subtitle).font(Theme.ui(13)).foregroundStyle(Theme.ink2).lineLimit(1)
                }
                Spacer()
            }

            ScrollView {
                WordRun(
                    spans: window,
                    currentIndex: reader.currentIndex,
                    font: Theme.serif(fontSize + 7),
                    color: Theme.ink,
                    dimBefore: true,
                    onTap: { reader.play(from: $0) }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 24)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)

            RibbonProgress(progress: document.progress) { fraction in
                let i = Int(Double(max(0, reader.text.spans.count - 1)) * fraction)
                reader.play(from: i)
            }
            HStack {
                Text(formatTimecode(elapsedEstimate)).font(Theme.mono(12)).foregroundStyle(Theme.ink2)
                Spacer()
                Text(formatMinutesLeft(reader.secondsLeftInChapter) + " in chapter").font(Theme.mono(12)).foregroundStyle(Theme.ink2)
                Spacer()
                Text(formatTimecode(totalEstimate)).font(Theme.mono(12)).foregroundStyle(Theme.ink2)
            }
            .padding(.top, 4)

            HStack(spacing: 28) {
                Spacer()
                Button { reader.skip(-15) } label: { Text("−15").font(Theme.mono(13)) }
                    .buttonStyle(PaperButtonStyle(size: 56))
                    .accessibilityLabel("Back 15 seconds")
                Button {
                    if !reader.isSpeaking || reader.isPaused { engine.playReading(document) } else { reader.pause() }
                } label: {
                    Image(systemName: reader.isSpeaking && !reader.isPaused ? "pause.fill" : "play.fill")
                        .font(.system(size: 28))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(PaperButtonStyle(size: 84, filled: true))
                .accessibilityLabel(reader.isSpeaking && !reader.isPaused ? "Pause" : "Play")
                Button { reader.skip(15) } label: { Text("+15").font(Theme.mono(13)) }
                    .buttonStyle(PaperButtonStyle(size: 56))
                    .accessibilityLabel("Forward 15 seconds")
                Spacer()
            }
            .padding(.top, 16)

            HStack {
                RateMenu()
                    .padding(.horizontal, 8)
                    .background(Capsule().stroke(Theme.line, lineWidth: 1))
                Spacer()
                Text(reader.voice?.name ?? "Voice")
                    .font(Theme.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
                    .frame(minHeight: 40).padding(.horizontal, 14)
                    .background(Capsule().stroke(Theme.line, lineWidth: 1))
                Spacer()
                HoldToNoteButton()
            }
            .padding(.top, 18)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    /// About two sentences before the spoken word and a few after it.
    private var window: ArraySlice<TimedSpan> {
        let spans = reader.text.spans
        guard !spans.isEmpty else { return spans[...] }
        let i = min(max(reader.currentIndex ?? 0, 0), spans.count - 1)
        let start = max(0, i - 24)
        let end = min(spans.count, i + 40)
        return spans[start..<end]
    }

    private var subtitle: String {
        let chapter = reader.chapters.indices.contains(reader.chapterIndex) ? reader.chapters[reader.chapterIndex].title : ""
        return document.author.isEmpty ? chapter : "\(document.author) · \(chapter)"
    }

    private var elapsedEstimate: TimeInterval {
        Double(reader.currentIndex ?? 0) / (2.6 * reader.rateMultiplier)
    }

    private var totalEstimate: TimeInterval {
        Double(reader.text.spans.count) / (2.6 * reader.rateMultiplier)
    }
}
