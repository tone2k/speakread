import SwiftUI

/// Recording. Closed: one column. Open: waveform on the left page, transcript on
/// the right. Laptop pose: transcript on the upright half, controls on the flat half.
struct RecordingView: View {
    @Environment(Engine.self) private var engine
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        GeometryReader { proxy in
            let fold = proxy.fold(horizontalSizeClass: horizontalSizeClass)
            Group {
                switch fold.pose {
                case .closed:
                    closedLayout
                case .openWide, .book:
                    Spread(fold: fold) {
                        leftPage
                    } trailing: {
                        transcriptPage(fontSize: 18)
                    }
                case .laptop, .openTall:
                    Spread(fold: fold) {
                        transcriptPage(fontSize: 23, showsHeader: true)
                    } trailing: {
                        lecternControls
                    }
                }
            }
            .animation(.smooth, value: fold)
        }
        .paperBackground()
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarPinnedTrailing) {
                Button("Done", systemImage: "stop.circle.fill") { Task { await engine.stopRecording() } }
                    .tint(Theme.ribbon)
            }
        }
        .onAppear { if !engine.recorder.isRecording { engine.startRecording() } }
    }

    // MARK: Closed

    private var closedLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            status
            timecode(size: 54)
                .padding(.top, 22)
            RibbonWaveform(levels: engine.recorder.levels, maxHeight: 72)
                .padding(.top, 18)
            transcript(fontSize: 20)
                .padding(.top, 20)
            controls(stopSize: 84, wide: false)
                .padding(.top, 16)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    // MARK: Open

    private var leftPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            status
            TextField("Title", text: Bindable(engine.recorder).title)
                .font(Theme.serif(34, weight: .medium))
                .foregroundStyle(Theme.ink)
                .textFieldStyle(.plain)
            timecode(size: 48)
            RibbonWaveform(levels: engine.recorder.levels, maxHeight: 64)
            marks
            Spacer(minLength: 0)
            controls(stopSize: 76, wide: true)
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 24)
    }

    private func transcriptPage(fontSize: CGFloat, showsHeader: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if showsHeader {
                status
            } else {
                HStack {
                    Text("Transcript · live").kicker()
                    Spacer()
                    Text(engine.recorder.earsName).font(Theme.ui(12)).foregroundStyle(Theme.ink2)
                }
            }
            transcript(fontSize: fontSize)
            Text("Lighter words are still settling · tap any word later to hear it")
                .font(Theme.ui(12))
                .foregroundStyle(Theme.ink2)
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 24)
    }

    private var lecternControls: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .firstTextBaseline) {
                timecode(size: 72)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(marksSummary).font(Theme.ui(13)).foregroundStyle(Theme.ink2)
                    Text(levelSummary).font(Theme.ui(13)).foregroundStyle(Theme.ink2)
                }
            }
            RibbonWaveform(levels: engine.recorder.levels, maxHeight: 80)
            Spacer(minLength: 0)
            controls(stopSize: 112, wide: true)
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 36)
    }

    // MARK: Pieces

    private var status: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.ribbon).frame(width: 10, height: 10)
                .overlay(Circle().stroke(Theme.ribbon.opacity(0.18), lineWidth: 4).padding(-4))
                .opacity(engine.recorder.isPaused ? 0.4 : 1)
            Text(engine.recorder.isPaused ? "Paused" : "Recording").font(Theme.ui(13, weight: .semibold)).foregroundStyle(Theme.ink)
            Text("· \(engine.recorder.earsName) · on this iPhone").font(Theme.ui(13)).foregroundStyle(Theme.ink2)
            Spacer()
        }
    }

    private func timecode(size: CGFloat) -> some View {
        let elapsed = engine.recorder.elapsed
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(formatTimecode(elapsed))
                .font(Theme.mono(size, weight: .medium))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            Text(".\(Int((elapsed - floor(elapsed)) * 10))")
                .font(Theme.mono(size * 0.4))
                .foregroundStyle(Theme.ink2)
            Spacer()
            Text(marksSummary).font(Theme.ui(13)).foregroundStyle(Theme.ink2)
        }
    }

    private func transcript(fontSize: CGFloat) -> some View {
        ScrollView {
            WordRun(spans: engine.recorder.transcript.spans[...], currentIndex: nil, font: Theme.serif(fontSize), color: Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
        .defaultScrollAnchor(.bottom)
        .frame(maxHeight: .infinity)
    }

    private var marks: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Marks").kicker().padding(.bottom, 6)
            if engine.recorder.marks.isEmpty {
                Text("Tap Mark to drop a chapter mark at this moment.")
                    .font(Theme.ui(13)).foregroundStyle(Theme.ink2)
            }
            ForEach(engine.recorder.marks) { mark in
                HStack(spacing: 14) {
                    Text(formatTimecode(mark.time)).font(Theme.mono(12)).foregroundStyle(Theme.ribbonInk).frame(width: 48, alignment: .leading)
                    Text(mark.label).font(Theme.ui(15)).foregroundStyle(Theme.ink)
                }
                .padding(.vertical, 9)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
        }
    }

    private func controls(stopSize: CGFloat, wide: Bool) -> some View {
        HStack {
            Button { engine.recorder.mark() } label: {
                Label("Mark", systemImage: "flag")
                    .frame(width: wide ? 120 : 76)
            }
            .buttonStyle(PaperButtonStyle(size: wide ? 64 : 52))
            Spacer()
            Button {
                Task { await engine.stopRecording() }
            } label: {
                RoundedRectangle(cornerRadius: stopSize * 0.08)
                    .fill(.white)
                    .frame(width: stopSize * 0.31, height: stopSize * 0.31)
            }
            .buttonStyle(RibbonButtonStyle(size: stopSize))
            .accessibilityLabel("Stop recording")
            Spacer()
            Button {
                if engine.recorder.isPaused { engine.recorder.resume() } else { engine.recorder.pause() }
            } label: {
                Label(engine.recorder.isPaused ? "Resume" : "Pause", systemImage: engine.recorder.isPaused ? "play.fill" : "pause.fill")
                    .frame(width: wide ? 120 : 76)
            }
            .buttonStyle(PaperButtonStyle(size: wide ? 64 : 52))
        }
    }

    private var marksSummary: String {
        let n = engine.recorder.marks.count
        return n == 1 ? "1 mark" : "\(n) marks"
    }

    private var levelSummary: String {
        let l = engine.recorder.level
        if l < 0.15 { return "Quiet · speak up a little" }
        if l > 0.9 { return "Loud · level is clipping" }
        return "Level good"
    }
}
