import SwiftUI

/// Tent pose at night: dark paper, ember red, the chapter, time left, a sleep timer.
/// A tap anywhere pauses or resumes, so there is nothing to find in the dark.
struct NightstandView: View {
    @Environment(Engine.self) private var engine
    let document: Document
    var onClose: () -> Void

    private var reader: Reader { engine.reader }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.night.ignoresSafeArea()
            RibbonTab(width: 14, height: 96, color: Theme.ember.opacity(0.9))
                .padding(.leading, 48)
                .ignoresSafeArea(edges: .top)

            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Nightstand").font(Theme.kicker()).textCase(.uppercase).kerning(1.2).foregroundStyle(Theme.ember.opacity(0.9))
                    Text(document.title).font(Theme.serif(34)).foregroundStyle(Theme.nightInk).padding(.top, 6).lineLimit(2)
                    Text(status).font(Theme.ui(15)).foregroundStyle(Theme.nightInk.opacity(0.7)).padding(.top, 6)
                    Spacer()
                    RibbonProgress(progress: document.progress, color: Theme.ember, track: Theme.nightInk.opacity(0.18))
                    HStack {
                        Text(formatMinutesLeft(reader.secondsLeftInChapter) + " in chapter")
                        Spacer()
                        Text(sleepLabel)
                    }
                    .font(Theme.mono(12)).foregroundStyle(Theme.nightInk.opacity(0.6))
                }
                .padding(.leading, 36)

                VStack(alignment: .trailing, spacing: 0) {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(context.date.formatted(.dateTime.hour().minute()))
                            .font(Theme.mono(64, weight: .medium))
                            .foregroundStyle(Theme.nightInk.opacity(0.85))
                    }
                    Spacer()
                    Menu {
                        ForEach([5, 15, 30, 45], id: \.self) { m in
                            Button("Sleep in \(m) min") { reader.setSleep(minutes: m) }
                        }
                        Button("No sleep timer") { reader.setSleep(minutes: nil) }
                    } label: {
                        Label("Sleep timer", systemImage: "moon.zzz")
                            .font(Theme.ui(13, weight: .medium))
                            .foregroundStyle(Theme.nightInk.opacity(0.8))
                            .frame(minHeight: 44)
                    }
                    Button { onClose() } label: {
                        Label("Leave Nightstand", systemImage: "sun.max")
                            .font(Theme.ui(13, weight: .medium))
                            .foregroundStyle(Theme.nightInk.opacity(0.8))
                            .frame(minHeight: 44)
                    }
                    Text("Tap anywhere to \(reader.isSpeaking && !reader.isPaused ? "pause" : "resume")")
                        .font(Theme.ui(12)).foregroundStyle(Theme.nightInk.opacity(0.55))
                        .padding(.top, 6)
                }
            }
            .padding(48)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !reader.isSpeaking || reader.isPaused { engine.playReading(document) } else { reader.pause() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .onAppear {
            if reader.sleepAt == nil { reader.setSleep(minutes: engine.settings.sleepMinutes) }
        }
    }

    private var status: String {
        let chapter = reader.chapters.indices.contains(reader.chapterIndex) ? reader.chapters[reader.chapterIndex].title : ""
        let voice = reader.voice?.name ?? "Verso"
        let state = reader.isSpeaking && !reader.isPaused ? "\(voice) is reading" : "Paused"
        return "\(chapter) · \(state)"
    }

    private var sleepLabel: String {
        guard let at = reader.sleepAt else { return "No sleep timer" }
        let m = max(0, Int(at.timeIntervalSinceNow / 60))
        return "Sleep in \(m) min"
    }
}
