import SwiftUI
import SwiftData

/// The closed phone. One hand, one thumb. The live strip up top, Said and
/// Read under one header switch, the record dock at the bottom.
struct PocketView: View {
    enum Side: String, CaseIterable {
        case said = "Said"
        case read = "Read"
    }

    @Environment(Engine.self) private var engine
    @Query(sort: \Document.createdAt, order: .reverse) private var documents: [Document]
    @State private var side: Side = .said
    let searchText: String

    private var shown: [Document] {
        documents.filter { ($0.kind == .recording) == (side == .said) && $0.matches(searchText) }
    }
    private var recordings: [Document] { documents.filter { $0.kind == .recording } }
    private var books: [Document] { documents.filter { $0.kind == .book } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                LiveStrip()
                header
                    .padding(.bottom, 14)
                if shown.isEmpty {
                    EmptySide(side: side)
                } else {
                    ForEach(shown) { document in
                        Button { engine.open(document) } label: { DocumentRow(document: document) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) { engine.delete(document) }
                            }
                    }
                }
            }
            .padding(.horizontal, HUD.Space.closedMargin)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { recordDock }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                segment("SAID \(recordings.count)", .said)
                Text("|")
                    .hudText(.title1)
                    .foregroundStyle(HUD.fg2)
                segment("READ \(books.count)", .read)
                Spacer(minLength: 0)
            }
            Text(subline)
                .hudText(.label)
                .foregroundStyle(HUD.fg1)
                .lineLimit(1)
        }
    }

    private func segment(_ title: String, _ value: Side) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) { side = value }
        } label: {
            Text(title)
                .hudText(.title1)
                .foregroundStyle(side == value ? HUD.fg0 : HUD.fg2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(side == value ? [.isSelected] : [])
    }

    private var subline: String {
        switch side {
        case .said:
            let total = recordings.reduce(0) { $0 + $1.duration }
            let hours = Int(total) / 3600
            let minutes = (Int(total) % 3600) / 60
            let length = hours > 0 ? "\(hours) H \(minutes) MIN" : "\(minutes) MIN"
            return "\(Self.dayStamp) · \(recordings.count) REC · \(length)"
        case .read:
            let inProgress = books.count { $0.progress > 0 && $0.progress < 1 }
            return "\(books.count) BOOKS · \(inProgress) IN PROGRESS"
        }
    }

    private static var dayStamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE dd MMM yyyy"
        return formatter.string(from: .now).uppercased()
    }

    private var recordDock: some View {
        // While recording, the dock steps aside entirely: the follow-me
        // transport strip already carries the REC clock, pause, mark and
        // stop, and its body opens the recording screen. A second big
        // orange block stacked on top of the strip was pure mass.
        Group {
            if !engine.recorder.isRecording {
                VStack(spacing: 10) {
                    Button {
                        engine.startRecording()
                    } label: {
                        Text("●").hudText(.title1)
                    }
                    .buttonStyle(SignalButtonStyle(size: 84))
                    .accessibilityLabel("Record")
                    Text("TAP TO RECORD")
                        .hudText(.label)
                        .foregroundStyle(HUD.fg1)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background {
                    HUD.bg0
                        .overlay(alignment: .top) { Rectangle().fill(HUD.rule).frame(height: 1) }
                        .ignoresSafeArea()
                }
            }
        }
    }
}

/// The trace strip, as a leaf: the recorder's elapsed clock re-runs this
/// view only, never the Pocket body (P2).
struct LiveStrip: View {
    @Environment(Engine.self) private var engine

    var body: some View {
        if engine.recorder.isRecording {
            Button {
                engine.startRecording()
            } label: {
                TraceStrip(text: "● REC \(formatTimecode(engine.recorder.elapsed)) · \(lastWords)")
            }
            .buttonStyle(.plain)
            .padding(.bottom, 20)
        } else if let continuing = engine.continuing {
            Button {
                engine.open(continuing)
            } label: {
                TraceStrip(text: continueText(continuing))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 20)
        }
    }

    private var lastWords: String {
        let tail = engine.recorder.tailText
        return tail.isEmpty ? "…" : "…" + String(tail.suffix(40))
    }

    private func continueText(_ document: Document) -> String {
        switch document.kind {
        case .recording:
            return "▶ REC \(formatTimecode(document.duration)) · \(document.title.uppercased())"
        case .book:
            if engine.reader.document?.id == document.id {
                let reader = engine.reader
                let base = "▶ READ CH \(Self.pad2(reader.chapterIndex + 1)) · ~\(max(0, reader.minutesLeft)) MIN LEFT"
                let percent = reader.progressPermille / 10
                return percent > 0 ? base + " · \(percent)%" : base
            }
            let minutes = Int(ceil(max(0, document.estimatedSecondsLeft) / 60))
            let base = "▶ READ CH \(Self.pad2(document.chapterIndex + 1)) · ~\(minutes) MIN LEFT"
            let percent = Int(document.progress * 100)
            return percent > 0 ? base + " · \(percent)%" : base
        }
    }

    static func pad2(_ value: Int) -> String { String(format: "%02d", value) }
}

struct EmptySide: View {
    let side: PocketView.Side

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(side == .said ? "NO RECORDINGS" : "NO BOOKS")
                .hudText(.title2)
                .foregroundStyle(HUD.fg0)
            Text(side == .said ? "Tap the red button and talk. Verso writes it down as you go." : "Add an EPUB or a PDF with the plus button. Verso reads it to you.")
                .hudText(.body)
                .foregroundStyle(HUD.fg1)
        }
        .padding(.top, 24)
    }
}
