import SwiftUI
import SwiftData

/// A finished recording: the transcript as one TextKit view with the
/// lock under the word being played. Tap a word and the audio goes
/// there. Open: controls and marks on the left page, transcript right.
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
                        titleField
                        transcript(fontSize: 19)
                        PlaybackProgress(document: document)
                        controls(large: false)
                    }
                    .padding(.horizontal, HUD.Space.closedMargin)
                    .padding(.vertical, 16)
                case .openWide, .book:
                    Spread(fold: fold) {
                        VStack(alignment: .leading, spacing: 18) {
                            PanelHeader(title: "A / PLAYBACK")
                            titleField
                            PlaybackTimecode(player: player, style: .display2, smallStyle: .meta)
                            PlaybackProgress(document: document)
                            marks
                            Spacer(minLength: 0)
                            controls(large: false)
                        }
                        .padding(.horizontal, 32)
                        .padding(.vertical, 24)
                    } trailing: {
                        VStack(alignment: .leading, spacing: 18) {
                            PanelHeader(title: "B / TRANSCRIPT")
                            transcript(fontSize: 18)
                        }
                        .padding(.horizontal, 32)
                        .padding(.vertical, 24)
                    }
                case .laptop, .openTall:
                    Spread(fold: fold) {
                        VStack(alignment: .leading, spacing: 18) {
                            titleField
                            transcript(fontSize: 22)
                        }
                        .padding(.horizontal, 32)
                        .padding(.vertical, 24)
                    } trailing: {
                        VStack(alignment: .leading, spacing: 26) {
                            PlaybackTimecode(player: player, style: .display0, smallStyle: .title1)
                            PlaybackProgress(document: document)
                            Spacer(minLength: 0)
                            controls(large: true)
                        }
                        .padding(.horizontal, 32)
                        .padding(.vertical, 36)
                    }
                }
            }
            .animation(.smooth(duration: 0.35), value: fold.pose)
        }
        .hudGround(grid: false)
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

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Title", text: $document.title)
                .hudText(.title2)
                .foregroundStyle(HUD.fg0)
                .textFieldStyle(.plain)
                .overlay(alignment: .bottom) { Rectangle().fill(HUD.rule).frame(height: 1) }
            Text("\(Self.stamp(document.createdAt)) · \(formatTimecode(document.duration))")
                .hudText(.meta)
                .foregroundStyle(HUD.fg1)
        }
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy HH:mm"
        return formatter.string(from: date).uppercased()
    }

    private func transcript(fontSize: CGFloat) -> some View {
        Group {
            if player.transcript.isEmpty {
                Text("No words were heard in this recording.")
                    .hudText(.body)
                    .foregroundStyle(HUD.fg1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // One TextKit view (P5); the lock layer follows by rect,
                // replacing the old per-word views and the every-40-words
                // scroll jump that skipped whenever the index jumped by 2.
                TimedTextView(
                    text: player.transcript,
                    currentIndex: player.currentIndex,
                    fontSize: fontSize,
                    dimBefore: true,
                    follows: true,
                    onTap: { i in
                        player.seek(toSpan: i)
                        if !player.isPlaying { player.play() }
                    }
                )
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var marks: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MARKS")
                .hudText(.label)
                .foregroundStyle(HUD.fg1)
                .padding(.bottom, 6)
            if document.marks.isEmpty {
                Text("No marks.")
                    .hudText(.body)
                    .foregroundStyle(HUD.fg1)
            }
            ForEach(document.marks) { mark in
                Button {
                    player.seek(to: mark.time)
                    if !player.isPlaying { player.play() }
                } label: {
                    HStack(spacing: 14) {
                        Text("T+" + formatTimecode(mark.time))
                            .hudText(.meta)
                            .foregroundStyle(HUD.signalInk)
                        Text(mark.label)
                            .hudText(.body)
                            .foregroundStyle(HUD.fg0)
                            .lineLimit(1)
                        Spacer()
                    }
                    .frame(height: 36)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) { Rectangle().fill(HUD.rule).frame(height: 1) }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func controls(large: Bool) -> some View {
        HStack(spacing: large ? 28 : 20) {
            Spacer()
            Button { player.skip(-15) } label: { Text("−15") }
                .buttonStyle(HUDButtonStyle(size: large ? 72 : 56))
                .accessibilityLabel("Back 15 seconds")
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: large ? 34 : 28))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(HUDButtonStyle(size: large ? 112 : 84, primary: true))
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Button { player.skip(15) } label: { Text("+15") }
                .buttonStyle(HUDButtonStyle(size: large ? 72 : 56))
                .accessibilityLabel("Forward 15 seconds")
            Menu {
                ForEach([0.8, 1.0, 1.2, 1.5, 2.0], id: \.self) { r in
                    Button(String(format: "%.1f×", r)) { player.rate = Float(r) }
                }
            } label: {
                Text(String(format: "%.1f×", player.rate))
                    .hudText(.meta)
                    .foregroundStyle(HUD.fg0)
                    .frame(minWidth: 44, minHeight: 44)
                    .padding(.horizontal, 6)
                    .overlay(Rectangle().strokeBorder(HUD.rule, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            Spacer()
        }
    }
}

/// The big clock as a leaf (P2): the 12 Hz player clock re-runs this
/// view only. No numeric transition (P21).
struct PlaybackTimecode: View {
    let player: Player
    let style: HUDTextStyle
    let smallStyle: HUDTextStyle

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(formatTimecode(player.currentTime))
                .hudText(style)
                .foregroundStyle(HUD.fg0)
            Text("/ \(formatTimecode(player.duration))")
                .hudText(smallStyle)
                .foregroundStyle(HUD.fg1)
        }
    }
}

/// Timeline + end readouts as a leaf, ticks at the marks.
struct PlaybackProgress: View {
    @Environment(Engine.self) private var engine
    let document: Document

    private var player: Player { engine.player }

    var body: some View {
        VStack(spacing: 2) {
            HUDTimeline(
                progress: player.duration > 0 ? player.currentTime / player.duration : 0,
                ticks: ticks
            ) { fraction in
                player.seek(to: fraction * player.duration)
            }
            HStack {
                Text(formatTimecode(player.currentTime))
                Spacer()
                Text(formatTimecode(player.duration))
            }
            .hudText(.meta)
            .foregroundStyle(HUD.fg1)
        }
    }

    private var ticks: [Double] {
        guard player.duration > 0 else { return [] }
        return document.marks.map { $0.time / player.duration }
    }
}
