import SwiftUI
import SwiftData

/// A book. Closed: Listening. Open flat or book pose: a two-page spread with the
/// ribbon on the spine. Laptop pose: the Lectern. Any pose: Nightstand on demand.
struct ReadingView: View {
    @Environment(Engine.self) private var engine
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var document: Document

    @State private var fontSize: CGFloat = 19
    @State private var showsTextSize = false
    @State private var showsNightstand = false
    @State private var showsNotes = false
    @State private var showsCast = false
    @State private var spreadPair: Int?
    /// The seam trace's Y in spread coordinates, reported by whichever
    /// page currently holds the spoken line.
    @State private var seamTraceY: CGFloat?
    /// Pagination is measured once per (chapter, size bucket, font size)
    /// instead of once per spoken word (P14).
    @State private var paginationCache = PaginationCache()

    private var reader: Reader { engine.reader }

    var body: some View {
        GeometryReader { proxy in
            let fold = proxy.fold(horizontalSizeClass: horizontalSizeClass)
            Group {
                if showsNightstand {
                    NightstandView(document: document) { showsNightstand = false }
                } else {
                    switch fold.pose {
                    case .closed:
                        ListeningView(document: document, fontSize: fontSize)
                    case .openWide, .book:
                        spread(fold: fold)
                    case .laptop, .openTall:
                        lectern(fold: fold)
                    }
                }
            }
            .animation(.smooth(duration: 0.35), value: fold.pose)
        }
        .hudGround(grid: false)
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("Contents", systemImage: "list.bullet") {
                    ForEach(Array(reader.chapters.enumerated()), id: \.offset) { i, chapter in
                        Button(chapter.title) { reader.goToChapter(i) }
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Notes", systemImage: "bookmark") { showsNotes = true }
                    .badge(document.notes.count)
            }
            if document.isDialogue {
                ToolbarItem(placement: .primaryAction) {
                    Button("Cast", systemImage: "person.2") { showsCast = true }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Text size", systemImage: "textformat.size") { showsTextSize = true }
                    .popover(isPresented: $showsTextSize) {
                        textSizeControl
                    }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Nightstand", systemImage: "moon") { showsNightstand = true }
            }
            ToolbarOverflowMenu {
                Button("Delete book", systemImage: "trash", role: .destructive) {
                    engine.delete(document)
                    engine.path.removeAll()
                }
            }
        }
        .sheet(isPresented: $showsNotes) {
            NotesSheet(document: document)
        }
        .sheet(isPresented: $showsCast) {
            CastSheet(document: document)
        }
        .onAppear {
            if reader.document?.id != document.id { reader.load(document) }
            reader.voice = engine.settings.voice
            reader.rateMultiplier = engine.settings.rateMultiplier
            // A dialogue shows its cast the first time it is opened.
            if document.isDialogue {
                let key = "castSeen-\(document.id.uuidString)"
                if !UserDefaults.standard.bool(forKey: key) {
                    UserDefaults.standard.set(true, forKey: key)
                    showsCast = true
                }
            }
        }
        .onChange(of: reader.chapterIndex) { spreadPair = nil }
    }

    // MARK: Spread

    private func spread(fold: Fold) -> some View {
        let pageSize = CGSize(width: max(100, fold.leadingWidth - 56), height: max(100, fold.size.height - 132))
        let pagination = paginationCache.pagination(for: reader.text, pageSize: pageSize, fontSize: fontSize, chapter: reader.chapterIndex)
        let currentPage = pagination.page(containing: reader.currentIndex ?? 0)
        let pair = spreadPair ?? currentPage / 2
        let left = pair * 2
        let right = left + 1
        let noted = notedSpans

        return Spread(fold: fold, traceY: reader.isSpeaking ? seamTraceY : nil, traceLeading: currentPage == left) {
            BookPage(
                spans: reader.text.spans[pagination.range(ofPage: left)],
                currentIndex: reader.currentIndex,
                noted: noted,
                header: document.title.uppercased(),
                headerTrailing: document.author,
                footer: String(format: "P.%03d", left + 1),
                footerTrailing: String(format: "%03d%%", reader.progressPermille / 10),
                fontSize: fontSize,
                edge: .leading,
                onTap: { reader.play(from: $0) },
                onLineMidY: { y in
                    if currentPage == left {
                        let value = y.map { $0 + BookPage.textTopInset }
                        DispatchQueue.main.async { seamTraceY = value }
                    }
                }
            )
        } trailing: {
            BookPage(
                spans: reader.text.spans[pagination.range(ofPage: right)],
                currentIndex: reader.currentIndex,
                noted: noted,
                header: "CH \(String(format: "%02d", reader.chapterIndex + 1)) · \(chapterTitle.uppercased())",
                headerTrailing: speakerName.map { "● \($0.uppercased())" } ?? "",
                footer: reader.voice?.name ?? "",
                footerTrailing: right < pagination.pageCount ? String(format: "P.%03d", right + 1) : "",
                fontSize: fontSize,
                edge: .trailing,
                onTap: { reader.play(from: $0) },
                onLineMidY: { y in
                    if currentPage == right {
                        let value = y.map { $0 + BookPage.textTopInset }
                        DispatchQueue.main.async { seamTraceY = value }
                    }
                }
            )
            .overlay(alignment: .bottomLeading) {
                ReadingTransport(document: document, compact: false)
                    .padding(.leading, 32)
                    .padding(.bottom, 32)
            }
        }
        .onChange(of: pair) { seamTraceY = nil }
        .gesture(
            DragGesture(minimumDistance: 40).onEnded { value in
                let pairs = (pagination.pageCount + 1) / 2
                withAnimation(.linear(duration: 0.18)) {
                    if value.translation.width < 0 { spreadPair = min(pair + 1, max(0, pairs - 1)) }
                    else { spreadPair = max(pair - 1, 0) }
                }
            }
        )
        .id(pair)
        .transition(.opacity)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: pair)
        .onChange(of: currentPage) { _, new in
            if spreadPair != nil, new / 2 != spreadPair { spreadPair = nil }
        }
    }

    // MARK: Lectern

    private func lectern(fold: Fold) -> some View {
        let topHeight = fold.frame == nil ? fold.size.height - 140 : fold.topHeight
        let pageSize = CGSize(width: max(100, fold.size.width - 56), height: max(100, topHeight - 132))
        let lecternFont = fontSize + 4
        let pagination = paginationCache.pagination(for: reader.text, pageSize: pageSize, fontSize: lecternFont, chapter: reader.chapterIndex)
        let page = pagination.page(containing: reader.currentIndex ?? 0)

        return Group {
            if fold.frame != nil {
                Spread(fold: fold) {
                    BookPage(
                        spans: reader.text.spans[pagination.range(ofPage: page)],
                        currentIndex: reader.currentIndex,
                        noted: notedSpans,
                        header: document.title.uppercased(),
                        headerTrailing: chapterTitle,
                        footer: "P \(page + 1) / \(pagination.pageCount)",
                        footerTrailing: "",
                        fontSize: lecternFont,
                        edge: .leading,
                        onTap: { reader.play(from: $0) }
                    )
                } trailing: {
                    // The stage: in a dialogue the flat half shows the cast,
                    // with the speaking character lit, above the transport.
                    VStack(spacing: 24) {
                        Spacer()
                        if reader.isDialogue {
                            CastStrip()
                                .padding(.horizontal, HUD.Space.paneMargin)
                        }
                        ReadingTransport(document: document, compact: false, large: !reader.isDialogue)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        BookPage(
                            spans: reader.text.spans[...],
                            currentIndex: reader.currentIndex,
                            noted: notedSpans,
                            header: document.title.uppercased(),
                            headerTrailing: chapterTitle,
                            footer: "",
                            footerTrailing: "",
                            fontSize: fontSize,
                            edge: .leading,
                            onTap: { reader.play(from: $0) }
                        )
                    }
                    ReadingTransport(document: document, compact: false)
                        .padding(.bottom, 24)
                }
            }
        }
    }

    private var chapterTitle: String {
        reader.chapters.indices.contains(reader.chapterIndex) ? reader.chapters[reader.chapterIndex].title : ""
    }

    /// The display name of whoever is speaking, in a dialogue.
    private var speakerName: String? {
        guard let speaker = reader.currentSpeaker else { return nil }
        return reader.member(for: speaker)?.name ?? Cast.displayName(speaker)
    }

    /// The reading size, set by slider (Tony's ask: more sizes, smaller
    /// floor — 10 pt — same 30 pt top, live readout). This is the one
    /// place the size is set; every pose derives from `fontSize`.
    private var textSizeControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TEXT SIZE")
                    .hudText(.label)
                    .foregroundStyle(HUD.fg1)
                Spacer()
                Text("\(Int(fontSize)) PT")
                    .hudText(.meta)
                    .foregroundStyle(HUD.fg0)
            }
            Slider(value: $fontSize, in: 10...30, step: 1)
                .tint(HUD.signal)
                .frame(width: 260)
            Text("The ribbon lies under the word being read.")
                .hudText(.body, size: fontSize)
                .foregroundStyle(HUD.fg0)
                .lineLimit(2)
                .frame(width: 260, alignment: .leading)
        }
        .padding(16)
        .presentationBackground(HUD.bg1)
        .presentationCompactAdaptation(.popover)
    }

    private var notedSpans: Set<Int> {
        Set(document.notes.filter { $0.chapterIndex == reader.chapterIndex }.map(\.spanIndex))
    }
}

/// One page of a book: running header, the words, page number.
struct BookPage: View {
    /// The text begins exactly this far below the page's top edge
    /// (top padding 24 + header strip 28 + spacing 16). The seam trace
    /// conversion in ReadingView depends on the constant.
    static let textTopInset: CGFloat = 24 + 28 + 16

    let spans: ArraySlice<TimedSpan>
    let currentIndex: Int?
    var noted: Set<Int> = []
    let header: String
    let headerTrailing: String
    let footer: String
    let footerTrailing: String
    let fontSize: CGFloat
    let edge: HorizontalEdge
    var onTap: ((Int) -> Void)?
    /// Lock line mid-Y in text coordinates, for the seam trace.
    var onLineMidY: ((CGFloat?) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelHeader(title: header, trailing: headerTrailing.isEmpty ? nil : headerTrailing)
            TimedTextView(
                text: TimedText(spans: Array(spans)),
                currentIndex: currentIndex,
                indexOffset: spans.startIndex,
                fontSize: fontSize,
                noted: noted,
                onTap: onTap,
                onLineMidY: onLineMidY
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
            Spacer(minLength: 0)
            HStack {
                Text(footer).hudText(.meta).foregroundStyle(HUD.fg1)
                Spacer()
                Text(footerTrailing).hudText(.meta).foregroundStyle(HUD.fg1)
            }
        }
        .padding(.leading, edge == .leading ? 32 : 24)
        .padding(.trailing, edge == .leading ? 24 : 32)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }
}

/// Play, skip, speed, and the hold-to-note button. One component for every pose.
struct ReadingTransport: View {
    @Environment(Engine.self) private var engine
    let document: Document
    var compact: Bool
    var large: Bool = false

    private var reader: Reader { engine.reader }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: large ? 28 : 8) {
                // In a dialogue the skip buttons move by line, not by time.
                Button { reader.skipTurn(-1) } label: { Text(reader.isDialogue ? "‹ LINE" : "−15") }
                    .buttonStyle(HUDButtonStyle(size: large ? 72 : 44))
                    .accessibilityLabel(reader.isDialogue ? "Previous line" : "Back 15 seconds")
                Button {
                    if !reader.isSpeaking || reader.isPaused { engine.playReading(document) } else { reader.pause() }
                } label: {
                    Image(systemName: reader.isSpeaking && !reader.isPaused ? "pause.fill" : "play.fill")
                        .font(.system(size: large ? 34 : 18))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(HUDButtonStyle(size: large ? 112 : 44, primary: true))
                .accessibilityLabel(reader.isSpeaking && !reader.isPaused ? "Pause" : "Play")
                Button { reader.skipTurn(1) } label: { Text(reader.isDialogue ? "LINE ›" : "+15") }
                    .buttonStyle(HUDButtonStyle(size: large ? 72 : 44))
                    .accessibilityLabel(reader.isDialogue ? "Next line" : "Forward 15 seconds")
                if !compact {
                    RateMenu()
                    Text("~\(reader.minutesLeft) MIN LEFT")
                        .hudText(.meta)
                        .foregroundStyle(HUD.fg1)
                        .padding(.trailing, 10)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .background(HUD.bg1)
            .clipShape(Chamfer(cut: 8))
            .overlay(Chamfer(cut: 8).stroke(HUD.ruleStrong, lineWidth: 1))

            if !compact {
                ReaderStreamLine(reader: reader)
                HoldToNoteButton(large: large)
            }
        }
    }
}

struct RateMenu: View {
    @Environment(Engine.self) private var engine

    var body: some View {
        Menu {
            ForEach([0.8, 1.0, 1.2, 1.5, 2.0], id: \.self) { r in
                Button(String(format: "%.1f×", r)) {
                    engine.settings.rateMultiplier = r
                    engine.reader.setRate(r)
                }
            }
        } label: {
            Text(String(format: "%.1f×", engine.reader.rateMultiplier))
                .hudText(.meta)
                .foregroundStyle(HUD.fg0)
                .frame(minWidth: 44, minHeight: 44)
                .padding(.horizontal, 6)
                .overlay(Rectangle().strokeBorder(HUD.rule, lineWidth: 1))
                .contentShape(Rectangle())
        }
    }
}

/// Hold, speak, let go. The note is pinned to the sentence being read.
struct HoldToNoteButton: View {
    @Environment(Engine.self) private var engine
    var large = false
    @State private var holding = false

    var body: some View {
        HStack(spacing: 10) {
            Text(holding ? "REC NOTE · RELEASE TO KEEP" : "● HOLD TO SAY A NOTE")
                .hudText(.label)
                .lineLimit(1)
            if holding, !engine.recorder.tailText.isEmpty {
                Text(String(engine.recorder.tailText.suffix(40)))
                    .hudText(.meta)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(holding ? HUD.onSignal : HUD.signalInk)
        .padding(.horizontal, 16)
        .frame(minHeight: large ? 64 : 44)
        .background(Chamfer(cut: 4).fill(holding ? HUD.signal : HUD.bg1))
        .overlay(Chamfer(cut: 4).stroke(holding ? HUD.signal : HUD.ruleStrong, lineWidth: 1))
        .contentShape(Chamfer(cut: 4))
        .sensoryFeedback(.impact(flexibility: .soft), trigger: holding)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !holding {
                        holding = true
                        engine.beginMarginNote()
                    }
                }
                .onEnded { _ in
                    holding = false
                    engine.endMarginNote()
                }
        )
        .accessibilityLabel("Hold to say a margin note")
    }
}

/// Every note on the book, in book order, with "Read my notes back".
struct NotesSheet: View {
    @Environment(Engine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    let document: Document

    private var notes: [Note] {
        document.notes.sorted { ($0.chapterIndex, $0.spanIndex) < ($1.chapterIndex, $1.spanIndex) }
    }

    var body: some View {
        NavigationStack {
            List {
                if notes.isEmpty {
                    Text("No notes yet. Hold the note button while a sentence is read and say what you think.")
                        .hudText(.body).foregroundStyle(HUD.fg1)
                        .listRowBackground(HUD.bg1)
                }
                ForEach(notes) { note in
                    Button {
                        engine.reader.goToChapter(note.chapterIndex)
                        engine.reader.currentIndex = note.spanIndex
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("CH \(String(format: "%02d", note.chapterIndex + 1)) · \(Self.stamp(note.createdAt))")
                                .hudText(.label)
                                .foregroundStyle(HUD.fg1)
                            if note.text.isEmpty {
                                Text("[NO WORDS HEARD]")
                                    .hudText(.body)
                                    .foregroundStyle(HUD.fg2)
                            } else {
                                Text(note.text)
                                    .hudText(.body)
                                    .foregroundStyle(HUD.fg0)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(HUD.bg1)
                }
                .onDelete { offsets in
                    let doomed = offsets.map { notes[$0] }
                    for note in doomed {
                        if let name = note.audioFileName { AudioStore.remove(name) }
                        engine.context?.delete(note)
                    }
                    try? engine.context?.save()
                }
            }
            .scrollContentBackground(.hidden)
            .background(HUD.bg1)
            .navigationTitle("Notes · \(notes.count)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    // 2e #4 (already in the 2b spec): the read-back action
                    // toggles to STOP while the reader is speaking.
                    Button(engine.reader.isSpeaking ? "Stop" : "Read notes back", systemImage: engine.reader.isSpeaking ? "stop.fill" : "person.wave.2") {
                        if engine.reader.isSpeaking {
                            engine.reader.stop()
                        } else {
                            engine.reader.speakNotes(notes, voice: engine.settings.personalVoice ?? engine.settings.voice)
                        }
                    }
                    .disabled(notes.isEmpty && !engine.reader.isSpeaking)
                }
            }
        }
        .presentationBackground(HUD.bg1)
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM HH:mm"
        return formatter.string(from: date).uppercased()
    }

    private func chapterTitle(_ i: Int) -> String {
        document.chapters.indices.contains(i) ? document.chapters[i].title : "Chapter \(i + 1)"
    }
}
