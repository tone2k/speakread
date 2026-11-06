import SwiftUI
import SwiftData

/// The open phone: Said on the left page, Read on the right, the seam as
/// the spine. Tall pose: one scroll, Said above Read.
struct ShelfView: View {
    @Environment(Engine.self) private var engine
    @Query(sort: \Document.createdAt, order: .reverse) private var documents: [Document]
    let fold: Fold
    let searchText: String

    private var recordings: [Document] { documents.filter { $0.kind == .recording && $0.matches(searchText) } }
    private var books: [Document] { documents.filter { $0.kind == .book && $0.matches(searchText) } }

    var body: some View {
        if fold.pose.foldIsVertical {
            Spread(fold: fold) {
                SaidPage(recordings: recordings)
            } trailing: {
                ReadPage(books: books, columns: shelfColumns(paneWidth: fold.trailingWidth))
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 36) {
                    SaidPage(recordings: recordings, scrolls: false)
                    ReadPage(books: books, columns: shelfColumns(paneWidth: fold.size.width), scrolls: false)
                }
            }
        }
    }
}

/// Cartridge columns for a pane of this width. A cell must never be
/// narrower than the cartridge's 150 pt design width plus its 12 pt
/// gutter: the old rule (4 columns for any pane over 520 pt) produced
/// ~141 pt cells on the Duo's spread, and the cards — then fixed at
/// 150 pt wide — overflowed into each other. The count follows the
/// pane, so cells are always honestly sized.
func shelfColumns(paneWidth: CGFloat) -> Int {
    let content = paneWidth - 64 // ReadPage's side margins
    return min(6, max(2, Int((content + 12) / 162)))
}

struct SaidPage: View {
    @Environment(Engine.self) private var engine
    let recordings: [Document]
    var scrolls = true

    private var groups: [(String, [Document])] {
        let calendar = Calendar.current
        var order: [String] = []
        var map: [String: [Document]] = [:]
        for d in recordings {
            let key: String
            if calendar.isDateInToday(d.createdAt) { key = "Today" }
            else if calendar.isDateInYesterday(d.createdAt) { key = "Yesterday" }
            else if let week = calendar.date(byAdding: .day, value: -7, to: .now), d.createdAt > week { key = "This week" }
            else { key = d.createdAt.formatted(.dateTime.month(.wide).year()) }
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(d)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        let content = LazyVStack(alignment: .leading, spacing: 0) {
            PanelHeader(title: "A / SAID", trailing: summary)
                .padding(.bottom, 10)
            if recordings.isEmpty {
                EmptySide(side: .said)
            }
            ForEach(groups, id: \.0) { group in
                HStack(spacing: 10) {
                    Text(group.0.uppercased())
                        .hudText(.label)
                        .foregroundStyle(HUD.fg1)
                    Rectangle().fill(HUD.rule).frame(height: 1)
                    Text("\(group.1.count)")
                        .hudText(.meta)
                        .foregroundStyle(HUD.fg2)
                }
                .padding(.top, 14)
                .padding(.bottom, 4)
                ForEach(group.1) { document in
                    Button { engine.open(document) } label: { DocumentRow(document: document) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) { engine.delete(document) }
                        }
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)

        if scrolls {
            ScrollView { content }
        } else {
            content
        }
    }

    private var summary: String {
        let total = recordings.reduce(0) { $0 + $1.duration }
        let h = Int(total) / 3600
        let m = (Int(total) % 3600) / 60
        let time = h > 0 ? "\(h) H \(m) MIN" : "\(m) MIN"
        return "\(recordings.count) REC · \(time)"
    }
}

struct ReadPage: View {
    @Environment(Engine.self) private var engine
    let books: [Document]
    var columns = 3
    var scrolls = true

    var body: some View {
        let continuing = books.first { $0.progress > 0 && $0.progress < 1 }
        let content = LazyVStack(alignment: .leading, spacing: 14) {
            PanelHeader(title: "B / READ", trailing: "\(books.count) BOOKS · \(books.count { $0.progress > 0 && $0.progress < 1 }) IN PROGRESS")
            if let continuing {
                continuePanel(continuing)
            }
            if books.isEmpty {
                EmptySide(side: .read)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
                ForEach(Array(books.enumerated()), id: \.element.id) { i, book in
                    Button { engine.open(book) } label: {
                        Cartridge(
                            title: book.title,
                            meta: book.author.isEmpty ? "\(book.chapters.count) CHAPTERS" : book.author,
                            progress: book.progress,
                            pattern: Cartridge.Pattern(rawValue: i % 4) ?? .solid
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) { engine.delete(book) }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
        .padding(.vertical, 24)

        if scrolls {
            ScrollView { content }
        } else {
            content
        }
    }

    private func continuePanel(_ document: Document) -> some View {
        Button { engine.open(document) } label: {
            HStack(spacing: 14) {
                CartridgeMini(progress: document.progress, width: 44, height: 60)
                VStack(alignment: .leading, spacing: 3) {
                    Text("CONTINUE")
                        .hudText(.label)
                        .foregroundStyle(HUD.signalInk)
                    Text(document.title)
                        .hudText(.title3)
                        .foregroundStyle(HUD.fg0)
                        .lineLimit(1)
                    Text(continueMeta(document))
                        .hudText(.meta)
                        .foregroundStyle(HUD.fg1)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(14)
            .background(HUD.bg1)
            .clipShape(Chamfer(cut: 8))
            .overlay(Chamfer(cut: 8).stroke(HUD.rule, lineWidth: 1))
            .overlay(alignment: .leading) {
                Rectangle().fill(HUD.signal).frame(width: 3).padding(.vertical, 8)
            }
            .contentShape(Chamfer(cut: 8))
        }
        .buttonStyle(.plain)
    }

    private func continueMeta(_ document: Document) -> String {
        if engine.reader.document?.id == document.id {
            let reader = engine.reader
            let base = "CH \(String(format: "%02d", reader.chapterIndex + 1)) · ~\(max(0, reader.minutesLeft)) MIN LEFT"
            let percent = reader.progressPermille / 10
            return percent > 0 ? base + " · \(percent)%" : base
        }
        let minutes = Int(ceil(max(0, document.estimatedSecondsLeft) / 60))
        let base = "CH \(String(format: "%02d", document.chapterIndex + 1)) · ~\(minutes) MIN LEFT"
        let percent = Int(document.progress * 100)
        return percent > 0 ? base + " · \(percent)%" : base
    }
}
