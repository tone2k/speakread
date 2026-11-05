import SwiftUI
import SwiftData

/// The closed phone. One hand, one thumb. Said on one tab, Read on the other,
/// the ribbon up top for whatever is in progress, the record button at the bottom.
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let continuing = engine.continuing {
                    ContinueCard(document: continuing)
                        .padding(.bottom, 26)
                }

                HStack(alignment: .firstTextBaseline, spacing: 22) {
                    ForEach(Side.allCases, id: \.self) { s in
                        Button(s.rawValue) { withAnimation(.snappy) { side = s } }
                            .buttonStyle(.plain)
                            .font(Theme.serif(44, weight: .medium))
                            .foregroundStyle(side == s ? Theme.ink : Theme.ink2.opacity(0.55))
                            .accessibilityAddTraits(side == s ? [.isSelected] : [])
                    }
                    Spacer()
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                        .font(Theme.ui(13))
                        .foregroundStyle(Theme.ink2)
                }
                .padding(.bottom, 18)

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
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    engine.startRecording()
                } label: {
                    Circle().fill(.white).frame(width: 28, height: 28)
                }
                .buttonStyle(RibbonButtonStyle())
                .accessibilityLabel("Record")
                Text("Tap to record")
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.ink2)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(Theme.paper.opacity(0.92))
        }
    }
}

/// "Continue": the ribbon hanging out of the book, with what it marks beside it.
struct ContinueCard: View {
    @Environment(Engine.self) private var engine
    let document: Document

    var body: some View {
        Button {
            engine.open(document)
        } label: {
            HStack(alignment: .top, spacing: 22) {
                RibbonTab(height: 96)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Continue").kicker()
                    Text(document.title)
                        .font(Theme.serif(20))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                    Text(detail)
                        .font(Theme.ui(13))
                        .foregroundStyle(Theme.ink2)
                }
                .padding(.top, 14)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private var detail: String {
        switch document.kind {
        case .book:
            let chapter = document.chapters.indices.contains(document.chapterIndex) ? document.chapters[document.chapterIndex].title : "Chapter \(document.chapterIndex + 1)"
            let reading = engine.reader.isSpeaking && !engine.reader.isPaused ? " · reading now" : ""
            return "\(chapter) · \(formatMinutesLeft(document.estimatedSecondsLeft))\(reading)"
        case .recording:
            return "\(formatTimecode(document.duration)) · \(document.createdAt.formatted(date: .abbreviated, time: .shortened))"
        }
    }
}

struct EmptySide: View {
    let side: PocketView.Side

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(side == .said ? "Nothing said yet." : "Nothing to read yet.")
                .font(Theme.serif(22))
                .foregroundStyle(Theme.ink)
            Text(side == .said ? "Tap the red button and talk. Verso writes it down as you go." : "Add an EPUB or a PDF with the plus button. Verso reads it to you.")
                .font(Theme.ui(15))
                .foregroundStyle(Theme.ink2)
        }
        .padding(.top, 24)
    }
}
