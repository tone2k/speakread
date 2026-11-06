import SwiftUI

/// Recording. Closed: one column. Open: controls and marks on the left
/// page, transcript on the right. Laptop pose: transcript on the upright
/// half, controls on the flat half. Fast values (elapsed, levels, marks)
/// live in leaf views so the screen body never re-runs at data rate (P2).
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
            .animation(.smooth(duration: 0.35), value: fold.pose)
        }
        .hudGround(grid: false)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: engine.recorder.isRecording)
        .sensoryFeedback(.selection, trigger: engine.recorder.marks.count)
        .sensoryFeedback(.selection, trigger: engine.recorder.isPaused)
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done", systemImage: "stop.circle.fill") { Task { await engine.stopRecording() } }
                    .tint(HUD.signal)
            }
        }
        .onAppear { if !engine.recorder.isRecording { engine.startRecording() } }
    }

    // MARK: Closed

    private var closedLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecorderStatusLine(recorder: engine.recorder)
            RecorderTimecode(recorder: engine.recorder, style: .display1, tenthsStyle: .title2)
                .padding(.top, 22)
            RecorderScope(recorder: engine.recorder, height: 72)
                .padding(.top, 18)
            transcript(fontSize: 20)
                .padding(.top, 20)
            controls(stopSize: 84, buttonSize: 52)
                .padding(.top, 16)
        }
        .padding(.horizontal, HUD.Space.closedMargin)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    // MARK: Open

    private var leftPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            RecorderStatusLine(recorder: engine.recorder)
            PanelHeader(title: "A / RECORD", trailing: engine.recorder.earsName.uppercased())
            TextField("Title", text: Bindable(engine.recorder).title)
                .hudText(.title2)
                .foregroundStyle(HUD.fg0)
                .textFieldStyle(.plain)
                .overlay(alignment: .bottom) { Rectangle().fill(HUD.rule).frame(height: 1) }
            HStack(alignment: .firstTextBaseline) {
                RecorderTimecode(recorder: engine.recorder, style: .display2, tenthsStyle: .body)
                Spacer()
                RecorderMarksReadout(recorder: engine.recorder)
            }
            RecorderScope(recorder: engine.recorder, height: 64)
            marksTable
            Spacer(minLength: 0)
            controls(stopSize: 76, buttonSize: 52)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .hudGround(grid: true)
    }

    private func transcriptPage(fontSize: CGFloat, showsHeader: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if showsHeader {
                RecorderStatusLine(recorder: engine.recorder)
            } else {
                PanelHeader(title: "B / TRANSCRIPT · LIVE", trailing: engine.recorder.earsName.uppercased())
            }
            transcript(fontSize: fontSize)
            Text("GREY WORDS ARE STILL SETTLING · TAP A WORD LATER TO HEAR IT")
                .hudText(.label)
                .foregroundStyle(HUD.fg2)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
    }

    private var lecternControls: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .firstTextBaseline) {
                RecorderTimecode(recorder: engine.recorder, style: .display0, tenthsStyle: .title1)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    RecorderMarksReadout(recorder: engine.recorder)
                    RecorderLevelReadout(recorder: engine.recorder)
                }
            }
            RecorderScope(recorder: engine.recorder, height: 80)
            Spacer(minLength: 0)
            controls(stopSize: 112, buttonSize: 64)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 36)
    }

    // MARK: Pieces

    /// Finals as settled words; the volatile tail rides as ONE extra
    /// non-final span, so it renders as a single fg2 run (P11).
    private func transcript(fontSize: CGFloat) -> some View {
        let recorder = engine.recorder
        var spans = recorder.finalText.spans
        if !recorder.tailText.isEmpty {
            spans.append(TimedSpan(id: spans.count, text: recorder.tailText, start: recorder.elapsed, end: recorder.elapsed, confidence: 0, isFinal: false))
        }
        return ScrollView {
            WordRun(spans: spans[...], currentIndex: nil, fontSize: fontSize)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
        .defaultScrollAnchor(.bottom)
        .frame(maxHeight: .infinity)
    }

    private var marksTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MARKS")
                .hudText(.label)
                .foregroundStyle(HUD.fg1)
                .padding(.bottom, 6)
            if engine.recorder.marks.isEmpty {
                Text("Tap MARK to drop a chapter mark at this moment.")
                    .hudText(.body)
                    .foregroundStyle(HUD.fg1)
                    .padding(.vertical, 6)
            }
            ForEach(engine.recorder.marks) { mark in
                HStack(spacing: 14) {
                    Text("T+" + formatTimecode(mark.time))
                        .hudText(.meta)
                        .foregroundStyle(HUD.signalInk)
                    Text(mark.label)
                        .hudText(.body)
                        .foregroundStyle(HUD.fg0)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(height: 36)
                .overlay(alignment: .bottom) { Rectangle().fill(HUD.rule).frame(height: 1) }
            }
        }
    }

    private func controls(stopSize: CGFloat, buttonSize: CGFloat) -> some View {
        HStack {
            Button { engine.recorder.mark() } label: {
                Text("⚑ MARK")
            }
            .buttonStyle(HUDButtonStyle(size: buttonSize))
            Spacer()
            Button {
                Task { await engine.stopRecording() }
            } label: {
                Text("■").hudText(.title2)
            }
            .buttonStyle(SignalButtonStyle(size: stopSize))
            .accessibilityLabel("Stop recording")
            Spacer()
            Button {
                if engine.recorder.isPaused { engine.recorder.resume() } else { engine.recorder.pause() }
            } label: {
                Text(engine.recorder.isPaused ? "▶ RESUME" : "❚❚ PAUSE")
            }
            .buttonStyle(HUDButtonStyle(size: buttonSize))
        }
    }
}

/// The status line: blinking square + REC state. A leaf so pause flips
/// don't re-run the screen.
struct RecorderStatusLine: View {
    let recorder: Recorder

    var body: some View {
        HStack(spacing: 10) {
            if recorder.isPaused {
                Rectangle().fill(HUD.fg1).frame(width: 8, height: 8)
            } else {
                BlinkDot()
            }
            Text(recorder.isPaused ? "❚❚ PAUSED" : "● REC · \(recorder.earsName.uppercased()) · LOCAL")
                .hudText(.label)
                .foregroundStyle(recorder.isPaused ? HUD.fg1 : HUD.fg0)
            Spacer()
        }
    }
}

/// The elapsed clock, tenths at the smaller style in fg1. No numeric
/// transition (P21): the digits simply change.
struct RecorderTimecode: View {
    let recorder: Recorder
    let style: HUDTextStyle
    let tenthsStyle: HUDTextStyle

    var body: some View {
        let elapsed = recorder.elapsed
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(formatTimecode(elapsed))
                .hudText(style)
                .foregroundStyle(HUD.fg0)
            Text(".\(Int((elapsed - floor(elapsed)) * 10))")
                .hudText(tenthsStyle)
                .foregroundStyle(HUD.fg1)
        }
    }
}

struct RecorderMarksReadout: View {
    let recorder: Recorder

    var body: some View {
        Text("\(recorder.marks.count) MARKS")
            .hudText(.meta)
            .foregroundStyle(HUD.fg1)
    }
}

struct RecorderLevelReadout: View {
    let recorder: Recorder

    var body: some View {
        let level = recorder.level
        Group {
            if level < 0.15 {
                Text("LEVEL LOW · SPEAK UP").foregroundStyle(HUD.caution)
            } else if level > 0.9 {
                Text("CLIPPING").foregroundStyle(HUD.caution)
            } else {
                Text("LEVEL OK").foregroundStyle(HUD.fg1)
            }
        }
        .hudText(.meta)
    }
}
