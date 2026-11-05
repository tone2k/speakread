import SwiftUI
import SwiftData

/// A finished recording: the transcript with the ribbon under the word being
/// played. Tap a word and the audio goes there. Open: transcript on the right page.
struct PlaybackView: View {
    @Environment(Engine.self) private var engine
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var document: Document

    private var player: Player { engine.player }

    var body: some View {
        GeometryReader { proxy in
            let fold = proxy.fold(horizontalSizeClass: horizontalSizeClass)
            Group {
                switch fold.pose {
                case .closed:
                    VStack(alignment: .leading, spacing: 18) {
                        titleField(size: 28)
                        transcript(fontSize: 19)
                        progress
                        controls(large: false)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                case .openWide, .book:
                    Spread(fold: fold) {
                        VStack(alignment: .leading, spacing: 18) {
                            titleField(size: 34)
                            timecode(size: 48)
                            progress
                            marks
                            Spacer(minLength: 0)
                            controls(large: false)
                        }
                        .padding(.horizontal, 44)
                        .padding(.vertical, 24)
                    } trailing: {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Transcript").kicker()
                            transcript(fontSize: 18)
                        }
                        .padding(.horizontal, 44)
                        .padding(.vertical, 24)
                    }
                case .laptop, .openTall:
                    Spread(fold: fold) {
                        VStack(alignment: .leading, spacing: 18) {
                            titleField(size: 28)
                            transcript(fontSize: 22)
                        }
                        .padding(.horizontal, 44)
                        .padding(.vertical, 24)
                    } trailing: {
                        VStack(alignment: .leading, spacing: 26) {
                            timecode(size: 64)
                            progress
                            Spacer(minLength: 0)
                            controls(large: true)
                        }
                        .padding(.horizontal, 44)
                        .padding(.vertical, 36)
                    }
                }
            }
            .animation(.smooth, value: fold)
        }
        .paperBackground()
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: document.transcript.plain, subject: Text(document.title)) {
                    Label("Share transcript", systemImage: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Read it back", systemImage: "person.wave.2") {
                    player.pause()
                    let spoken = Document(kind: .book, title: document.title)
                    spoken.chapters = [Chapter(title: document.title, text: document.transcript.plain)]
                    engine.reader.load(spoken)
                    engine.reader.voice = engine.settings.personalVoice ?? engine.settings.voice
                    engine.reader.play(from: 0)
                }
            }
            ToolbarOverflowMenu {
                Button("Delete recording", systemImage: "trash", role: .destructive) {
                    engine.delete(document)
                    engine.path.removeAll()
                }
            }
        }
        .onAppear {
            if player.document?.id != document.id { player.load(document) }
        }
        .onDisappear { player.pause() }
    }

    private func titleField(size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Title", text: $document.title)
                .font(Theme.serif(size, weight: .medium))
                .foregroundStyle(Theme.ink)
                .textFieldStyle(.plain)
            Text("\(document.createdAt.formatted(date: .long, time: .shortened)) · \(formatTimecode(document.duration))")
                .font(Theme.ui(12)).foregroundStyle(Theme.ink2)
        }
    }

    private func timecode(size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(formatTimecode(player.currentTime)).font(Theme.mono(size, weight: .medium)).foregroundStyle(Theme.ink).contentTransition(.numericText())
            Text("/ \(formatTimecode(player.duration))").font(Theme.mono(size * 0.35)).foregroundStyle(Theme.ink2)
        }
    }

    private func transcript(fontSize: CGFloat) -> some View {
        ScrollViewReader { scroller in
            ScrollView {
                if player.transcript.isEmpty {
                    Text("No words were heard in this recording.").font(Theme.ui(15)).foregroundStyle(Theme.ink2)
                }
                WordRun(spans: player.transcript.spans[...], currentIndex: player.currentIndex, font: Theme.serif(fontSize), color: Theme.ink, dimBefore: true, onTap: { i in
                    player.seek(toSpan: i)
                    if !player.isPlaying { player.play() }
                })
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: player.currentIndex) { _, new in
                if let new, new % 40 == 0 { withAnimation { scroller.scrollTo(new, anchor: .center) } }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var progress: some View {
        VStack(spacing: 6) {
            RibbonProgress(progress: player.duration > 0 ? player.currentTime / player.duration : 0) { fraction in
                player.seek(to: fraction * player.duration)
            }
            HStack {
                Text(formatTimecode(player.currentTime)).font(Theme.mono(12)).foregroundStyle(Theme.ink2)
                Spacer()
                Text(formatTimecode(player.duration)).font(Theme.mono(12)).foregroundStyle(Theme.ink2)
            }
        }
    }

    private var marks: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Marks").kicker().padding(.bottom, 6)
            if document.marks.isEmpty {
                Text("No marks.").font(Theme.ui(13)).foregroundStyle(Theme.ink2)
            }
            ForEach(document.marks) { mark in
                Button {
                    player.seek(to: mark.time)
                    if !player.isPlaying { player.play() }
                } label: {
                    HStack(spacing: 14) {
                        Text(formatTimecode(mark.time)).font(Theme.mono(12)).foregroundStyle(Theme.ribbonInk).frame(width: 48, alignment: .leading)
                        Text(mark.label).font(Theme.ui(15)).foregroundStyle(Theme.ink)
                        Spacer()
                    }
                    .padding(.vertical, 9)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func controls(large: Bool) -> some View {
        HStack(spacing: large ? 28 : 20) {
            Spacer()
            Button { player.skip(-15) } label: { Text("−15").font(Theme.mono(large ? 16 : 13)) }
                .buttonStyle(PaperButtonStyle(size: large ? 72 : 56))
                .accessibilityLabel("Back 15 seconds")
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: large ? 34 : 28))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PaperButtonStyle(size: large ? 112 : 84, filled: true))
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Button { player.skip(15) } label: { Text("+15").font(Theme.mono(large ? 16 : 13)) }
                .buttonStyle(PaperButtonStyle(size: large ? 72 : 56))
                .accessibilityLabel("Forward 15 seconds")
            Menu {
                ForEach([0.8, 1.0, 1.2, 1.5, 2.0], id: \.self) { r in
                    Button(String(format: "%.1f×", r)) { player.rate = Float(r) }
                }
            } label: {
                Text(String(format: "%.1f×", player.rate))
                    .font(Theme.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
                    .frame(minWidth: 44, minHeight: 44)
            }
            Spacer()
        }
    }
}
