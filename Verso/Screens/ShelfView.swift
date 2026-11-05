import SwiftUI
import SwiftData

/// The open phone: Said on the left page, Read on the right, the fold as the spine.
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
                ReadPage(books: books, columns: fold.trailingWidth > 520 ? 4 : 3)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    SaidPage(recordings: recordings, scrolls: false)
                    ReadPage(books: books, columns: max(3, Int(fold.size.width / 170)), scrolls: false)
                }
            }
        }
    }
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
        let content = VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("Said").font(Theme.serif(42, weight: .medium)).foregroundStyle(Theme.ink)
                Text(summary).font(Theme.ui(13)).foregroundStyle(Theme.ink2)
            }
            .padding(.bottom, 10)
            if recordings.isEmpty {
                EmptySide(side: .said)
            }
            ForEach(groups, id: \.0) { group in
                Text(group.0).kicker().padding(.top, 14).padding(.bottom, 4)
                ForEach(group.1) { document in
                    Button { engine.open(document) } label: { DocumentRow(document: document) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) { engine.delete(document) }
                        }
                }
            }
        }
        .padding(.horizontal, 44)
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
        let time = h > 0 ? "\(h) h \(m) min" : "\(m) min"
        return "\(recordings.count) recordings · \(time)"
    }
}

struct ReadPage: View {
    @Environment(Engine.self) private var engine
    let books: [Document]
    var columns = 3
    var scrolls = true

    var body: some View {
        let continuing = books.first { $0.progress > 0 && $0.progress < 1 }
        let content = VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("Read").font(Theme.serif(42, weight: .medium)).foregroundStyle(Theme.ink)
                Text("\(books.count) books · \(books.filter { $0.progress > 0 && $0.progress < 1 }.count) in progress")
                    .font(Theme.ui(13)).foregroundStyle(Theme.ink2)
            }
            if let continuing {
                Button { engine.open(continuing) } label: {
                    HStack(spacing: 14) {
                        CoverThumb(title: continuing.title, progress: continuing.progress, width: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Continue").kicker()
                            Text(continuing.title).font(Theme.serif(18)).foregroundStyle(Theme.ink).lineLimit(1)
                            Text("\(chapterTitle(continuing)) · \(formatMinutesLeft(continuing.estimatedSecondsLeft)) · \(Int(continuing.progress * 100))%")
                                .font(Theme.ui(12)).foregroundStyle(Theme.ink2)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .topTrailing) { RibbonTab(width: 10, height: 44).padding(.trailing, 18) }
                }
                .buttonStyle(.plain)
            }
            if books.isEmpty {
                EmptySide(side: .read)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
                ForEach(Array(books.enumerated()), id: \.element.id) { i, book in
                    Button { engine.open(book) } label: { BookCover(document: book, variant: i % 4) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) { engine.delete(book) }
                        }
                }
            }
        }
        .padding(.leading, 36)
        .padding(.trailing, 24)
        .padding(.vertical, 24)

        if scrolls {
            ScrollView { content }
        } else {
            content
        }
    }

    private func chapterTitle(_ d: Document) -> String {
        d.chapters.indices.contains(d.chapterIndex) ? d.chapters[d.chapterIndex].title : "Chapter \(d.chapterIndex + 1)"
    }
}

/// A typographic cover. Four paper tints, so a shelf has rhythm without artwork.
struct BookCover: View {
    let document: Document
    let variant: Int

    private var background: Color {
        switch variant {
        case 0: return Theme.card
        case 1: return Theme.ink
        case 2: return Color(red: 0.812, green: 0.776, blue: 0.706)
        default: return Theme.night
        }
    }

    private var foreground: Color {
        variant == 1 || variant == 3 ? Theme.nightInk : Theme.ink
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(document.title)
                .font(Theme.serif(15, weight: .medium))
                .foregroundStyle(foreground)
                .lineLimit(3)
            Text(document.author.isEmpty ? "\(document.chapters.count) chapters" : document.author)
                .font(Theme.ui(10))
                .foregroundStyle(foreground.opacity(0.75))
                .lineLimit(2)
            Spacer(minLength: 8)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(foreground.opacity(0.25)).frame(height: 2)
                    Rectangle().fill(Theme.ribbon).frame(width: geo.size.width * document.progress, height: 2)
                }
            }
            .frame(height: 2)
        }
        .padding(12)
        .frame(height: 150)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(background))
        .shadow(color: Theme.ink.opacity(0.10), radius: 8, y: 6)
    }
}
