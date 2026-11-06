import SwiftUI

/// Tent pose at night: black ground, red lens only — no white, no blue,
/// no signal orange. A tap anywhere pauses or resumes, so there is
/// nothing to find in the dark.
struct NightstandView: View {
    @Environment(Engine.self) private var engine
    let document: Document
    var onClose: () -> Void

    private var reader: Reader { engine.reader }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HUD.Night.bg.ignoresSafeArea()

            // Chapter progress down the leading edge: a 3 pt bar whose
            // height is the fraction of the chapter read.
            GeometryReader { geo in
                Rectangle()
                    .fill(HUD.Night.n0)
                    .frame(width: 3, height: geo.size.height * chapterProgress)
            }
            .ignoresSafeArea()

            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("NIGHTSTAND")
                        .hudText(.label)
                        .foregroundStyle(HUD.Night.n1)
                    Text(document.title)
                        .hudText(.title2)
                        .foregroundStyle(HUD.Night.n0)
                        .padding(.top, 6)
                        .lineLimit(2)
                    Text(status)
                        .hudText(.title3, size: 15)
                        .foregroundStyle(HUD.Night.n1)
                        .padding(.top, 6)
                    Spacer()
                    NightTrack()
                    HStack {
                        Text("~\(minutesInChapter) MIN IN CH")
                        Spacer()
                        NightSleepReadout()
                    }
                    .hudText(.body, size: 14)
                    .foregroundStyle(HUD.Night.n1)
                    .padding(.top, 6)
                }
                .padding(.leading, 36)

                VStack(alignment: .trailing, spacing: 0) {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(context.date.formatted(.dateTime.hour().minute()))
                            .hudText(.display1, size: 64)
                            .foregroundStyle(HUD.Night.n0)
                    }
                    Spacer()
                    Menu {
                        ForEach([5, 15, 30, 45], id: \.self) { m in
                            Button("Sleep in \(m) min") { reader.setSleep(minutes: m) }
                        }
                        Button("No sleep timer") { reader.setSleep(minutes: nil) }
                    } label: {
                        Text("SLEEP TIMER")
                            .hudText(.label)
                            .foregroundStyle(HUD.Night.n1)
                            .frame(minHeight: 44)
                    }
                    Button { onClose() } label: {
                        Text("EXIT NIGHTSTAND")
                            .hudText(.label)
                            .foregroundStyle(HUD.Night.n1)
                            .frame(minHeight: 44)
                    }
                    Text("TAP ANYWHERE TO \(reader.isSpeaking && !reader.isPaused ? "PAUSE" : "RESUME")")
                        .hudText(.label)
                        .foregroundStyle(HUD.Night.n1)
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
        .onAppear {
            if reader.sleepAt == nil { reader.setSleep(minutes: engine.settings.sleepMinutes) }
        }
    }

    private var chapterProgress: Double {
        let count = reader.text.spans.count
        guard count > 0 else { return 0 }
        return Double((reader.currentIndex ?? 0) + 1) / Double(count)
    }

    private var minutesInChapter: Int {
        Int(ceil(max(0, reader.secondsLeftInChapter) / 60))
    }

    private var status: String {
        let voice = (reader.voice?.name ?? "Verso").uppercased()
        let state = reader.isSpeaking && !reader.isPaused ? "READING" : "READING PAUSED"
        return "CH \(String(format: "%02d", reader.chapterIndex + 1)) · \(voice) \(state)"
    }
}

/// The bottom progress track: 2 pt, n2 under n0.
struct NightTrack: View {
    @Environment(Engine.self) private var engine

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(HUD.Night.n2).frame(height: 2)
                Rectangle().fill(HUD.Night.n0).frame(width: geo.size.width * fraction, height: 2)
            }
        }
        .frame(height: 2)
    }

    private var fraction: Double {
        let reader = engine.reader
        let count = reader.text.spans.count
        guard count > 0 else { return 0 }
        return Double((reader.currentIndex ?? 0) + 1) / Double(count)
    }
}

/// The sleep countdown, re-read every minute — the old label read
/// `sleepAt` once and went stale (bug #5).
struct NightSleepReadout: View {
    @Environment(Engine.self) private var engine

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            if let at = engine.reader.sleepAt {
                Text("SLEEP T−\(max(0, Int(at.timeIntervalSinceNow / 60))) MIN")
            } else {
                Text("NO SLEEP TIMER")
            }
        }
    }
}
