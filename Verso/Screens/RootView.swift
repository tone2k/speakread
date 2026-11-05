import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(Engine.self) private var engine

    var body: some View {
        @Bindable var engine = engine
        NavigationStack(path: $engine.path) {
            HomeView()
                .navigationDestination(for: Engine.Route.self) { route in
                    switch route {
                    case .recording:
                        RecordingView()
                    case .reading(let id):
                        if let document = engine.document(id: id) {
                            ReadingView(document: document)
                        } else {
                            MissingView()
                        }
                    case .playback(let id):
                        if let document = engine.document(id: id) {
                            PlaybackView(document: document)
                        } else {
                            MissingView()
                        }
                    case .settings:
                        SettingsView()
                    }
                }
        }
        .alert("Verso", isPresented: Binding(get: { engine.lastError != nil }, set: { if !$0 { engine.lastError = nil } })) {
            Button("OK") { engine.lastError = nil }
        } message: {
            Text(engine.lastError ?? "")
        }
    }
}

private struct MissingView: View {
    var body: some View {
        ContentUnavailableView("That item is gone", systemImage: "book.closed")
            .paperBackground()
    }
}

/// The home screen: Pocket when the phone is closed, the Shelf when it is open.
struct HomeView: View {
    @Environment(Engine.self) private var engine
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var searchText = ""
    @State private var showsImporter = false

    var body: some View {
        GeometryReader { proxy in
            let fold = proxy.fold(horizontalSizeClass: horizontalSizeClass)
            Group {
                if fold.pose == .closed {
                    PocketView(searchText: searchText)
                } else {
                    ShelfView(fold: fold, searchText: searchText)
                }
            }
            .animation(.smooth, value: fold)
        }
        .paperBackground()
        .navigationTitle("Verso")
        .toolbarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search what you said and read")
        .toolbar {
            ToolbarItem(placement: .topBarPinnedTrailing) {
                Button("Record", systemImage: "record.circle.fill") { engine.startRecording() }
                    .tint(Theme.ribbon)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Add a book or audio", systemImage: "plus") { showsImporter = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Ears & Voice", systemImage: "slider.horizontal.3") { engine.path.append(.settings) }
            }
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: Importer.readableTypes, allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task {
                for url in urls { await engine.importFile(at: url) }
            }
        }
        .overlay {
            if engine.isImporting {
                ProgressView("Reading the file…")
                    .padding(24)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

/// One recording or book in a list.
struct DocumentRow: View {
    let document: Document

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(document.title)
                    .font(Theme.ui(17, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer()
                Text(trailing)
                    .font(Theme.mono(13))
                    .foregroundStyle(Theme.ink2)
            }
            Text(document.firstLine)
                .font(Theme.serif(16))
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
            Text(subtitle)
                .font(Theme.ui(12))
                .foregroundStyle(Theme.ink2)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        .contentShape(Rectangle())
    }

    private var trailing: String {
        switch document.kind {
        case .recording: return formatTimecode(document.duration)
        case .book: return "\(Int(document.progress * 100))%"
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if document.kind == .book, !document.author.isEmpty { parts.append(document.author) }
        parts.append(document.createdAt.formatted(date: .abbreviated, time: .shortened))
        let marks = document.marks.count
        if marks > 0 { parts.append(marks == 1 ? "1 mark" : "\(marks) marks") }
        let notes = document.notes.count
        if notes > 0 { parts.append(notes == 1 ? "1 note" : "\(notes) notes") }
        return parts.joined(separator: " · ")
    }
}

extension Document {
    func matches(_ search: String) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return true }
        if title.localizedCaseInsensitiveContains(q) || author.localizedCaseInsensitiveContains(q) { return true }
        switch kind {
        case .recording: return transcript.plain.localizedCaseInsensitiveContains(q)
        case .book: return chapters.contains { $0.text.localizedCaseInsensitiveContains(q) }
        }
    }
}
