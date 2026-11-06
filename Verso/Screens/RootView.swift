import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(Engine.self) private var engine
    @Environment(\.scenePhase) private var scenePhase

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
        // Appearance is Tony's choice (Settings): HUD tokens resolve per
        // scheme; Nightstand keeps its red lens in both modes.
        .preferredColorScheme(engine.settings.appearance.colorScheme)
        // Save points (P4): backgrounding is one; the rest live in Reader.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { engine.reader.savePosition() }
        }
        .onChange(of: engine.path) { engine.refreshContinuing() }
    }
}

private struct MissingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ITEM NOT FOUND")
                .hudText(.title2)
                .foregroundStyle(HUD.fg1)
            Text("It was deleted or moved.")
                .hudText(.body)
                .foregroundStyle(HUD.fg2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(HUD.Space.closedMargin)
        .hudGround(grid: false)
    }
}

/// The home screen: Pocket when the phone is closed, the Shelf when it is open.
struct HomeView: View {
    @Environment(Engine.self) private var engine
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var searchText = ""
    /// Debounced before it reaches the lists (P17): a keystroke must not
    /// re-filter — and re-fold — the whole library.
    @State private var debouncedSearch = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var showsImporter = false

    var body: some View {
        GeometryReader { proxy in
            let fold = proxy.fold(horizontalSizeClass: horizontalSizeClass)
            Group {
                if fold.pose == .closed {
                    PocketView(searchText: debouncedSearch)
                } else {
                    ShelfView(fold: fold, searchText: debouncedSearch)
                }
            }
            .animation(.smooth(duration: 0.35), value: fold.pose)
        }
        .hudGround(grid: true)
        .onChange(of: searchText) { _, new in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                if !Task.isCancelled { debouncedSearch = new }
            }
        }
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search what you said and read")
        .toolbar {
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
                HStack(spacing: 10) {
                    Text("IMPORTING")
                        .hudText(.label)
                        .foregroundStyle(HUD.fg0)
                    BlinkDot()
                    BlinkDot()
                    BlinkDot()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(HUD.bg1)
                .clipShape(Chamfer(cut: 8))
                .overlay(Chamfer(cut: 8).stroke(HUD.ruleStrong, lineWidth: 1))
            }
        }
    }
}

/// One recording or book in a list: the HUD DataRow, plus the summary
/// generation side effect.
struct DocumentRow: View {
    let document: Document

    var body: some View {
        DataRow(
            title: document.title,
            trailing: trailing,
            summary: document.summary ?? document.firstLine,
            meta: meta,
            progress: progress
        )
        .task { Summarizer.generateIfNeeded(for: document) }
    }

    private var trailing: String {
        switch document.kind {
        case .recording: return formatTimecode(document.duration)
        case .book:
            // 0% means nothing — no readout until there is progress.
            let percent = Int(document.progress * 100)
            return percent > 0 ? String(format: "%03d%%", percent) : ""
        }
    }

    private var meta: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM HH:mm"
        var parts = [formatter.string(from: document.createdAt).uppercased()]
        if document.isMeeting { parts.insert(document.digest == nil ? "MEETING" : "MEETING · DIGEST", at: 0) }
        if document.isDialogue { parts.insert("DIALOGUE", at: 0) }
        let marks = document.marks.count
        if marks > 0 { parts.append(marks == 1 ? "1 MARK" : "\(marks) MARKS") }
        let notes = document.notes.count
        if notes > 0 { parts.append(notes == 1 ? "1 NOTE" : "\(notes) NOTES") }
        return parts.joined(separator: " · ")
    }

    /// The 20-cell bar appears only under in-progress books (spec 2b).
    private var progress: Double? {
        guard document.kind == .book else { return nil }
        let value = document.progress
        return value > 0 && value < 1 ? value : nil
    }
}

extension Document {
    /// Folded once per query against the cached folded library text
    /// (P17) — no per-keystroke, per-document chapter scans.
    func matches(_ search: String) -> Bool {
        let q = search.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return true }
        return foldedSearchText.contains(q)
    }
}

extension Settings.AppearanceChoice {
    /// System follows the phone; Light/Dark pin the scheme. HUD tokens
    /// and Nightstand's red lens behave accordingly (Nightstand never
    /// adapts — it is red in both).
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
