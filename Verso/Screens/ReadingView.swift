import SwiftUI
import SwiftData

/// A book. Closed: Listening. Open flat or book pose: a two-page spread with the
/// ribbon on the spine. Laptop pose: the Lectern. Any pose: Nightstand on demand.
struct ReadingView: View {
    @Environment(Engine.self) private var engine
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var document: Document

    @State private var fontSize: CGFloat = 19
    @State private var showsNightstand = false
    @State private var showsNotes = false
    @State private var spreadPair: Int?

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
            .animation(.smooth, value: fold)
        }
        .paperBackground()
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
            ToolbarItem(placement: .primaryAction) {
                Menu("Text size", systemImage: "textformat.size") {
                    Button("Smaller") { fontSize = max(14, fontSize - 2) }
                    Button("Larger") { fontSize = min(30, fontSize + 2) }
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
        .onAppear {
            if reader.document?.id != document.id { reader.load(document) }
            reader.voice = engine.settings.voice
            reader.rateMultiplier = engine.settings.rateMultiplier
        }
        .onChange(of: reader.chapterIndex) { spreadPair = nil }
    }

    // MARK: Spread

    private func spread(fold: Fold) -> some View {
        let header = 60.0
        let footer = 48.0
        let pageSize = CGSize(width: max(100, fold.leadingWidth - 96), height: max(100, fold.size.height - header - footer - 48))
        let pagination = Pagination(text: reader.text, pageSize: pageSize, fontSize: fontSize)
        let currentPage = pagination.page(containing: reader.currentIndex ?? 0)
        let pair = spreadPair ?? currentPage / 2
        let left = pair * 2
        let right = left + 1
        let noted = notedSpans

        return Spread(fold: fold) {
            BookPage(
                spans: reader.text.spans[pagination.range(ofPage: left)],
                currentIndex: reader.currentIndex,
                noted: noted,
                header: document.title.uppercased(),
                headerTrailing: document.author,
                footer: "\(left + 1)",
                footerTrailing: "\(Int(document.progress * 100))%",
                fontSize: fontSize,
                edge: .leading,
                onTap: { reader.play(from: $0) }
            )
        } trailing: {
            BookPage(
                spans: reader.text.spans[pagination.range(ofPage: right)],
                currentIndex: reader.currentIndex,
                noted: noted,
                header: chapterTitle.uppercased(),
                headerTrailing: "",
                footer: reader.voice?.name ?? "",
                footerTrailing: right < pagination.pageCount ? "\(right + 1)" : "",
                fontSize: fontSize,
                edge: .trailing,
                onTap: { reader.play(from: $0) }
            )
            .overlay(alignment: .bottomLeading) {
                ReadingTransport(document: document, compact: false)
                    .padding(.leading, 44)
                    .padding(.bottom, 44)
            }
        }
        .overlay(alignment: .top) {
            // The ribbon lies on the spine, down to the line being read.
            if let frame = fold.frame {
                RibbonTab(width: 12, height: 120)
                    .offset(x: frame.midX - fold.size.width / 2)
                    .allowsHitTesting(false)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 40).onEnded { value in
                let pairs = (pagination.pageCount + 1) / 2
                withAnimation(.easeInOut(duration: 0.25)) {
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
        let pageSize = CGSize(width: max(100, fold.size.width - 88), height: max(100, topHeight - 120))
        let lecternFont = fontSize + 4
        let pagination = Pagination(text: reader.text, pageSize: pageSize, fontSize: lecternFont)
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
                        footer: "\(page + 1) of \(pagination.pageCount)",
                        footerTrailing: "",
                        fontSize: lecternFont,
                        edge: .leading,
                        onTap: { reader.play(from: $0) }
                    )
                } trailing: {
                    VStack {
                        Spacer()
                        ReadingTransport(document: document, compact: false, large: true)
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

    private var notedSpans: Set<Int> {
        Set(document.notes.filter { $0.chapterIndex == reader.chapterIndex }.map(\.spanIndex))
    }
}

/// One page of a book: running header, the words, page number.
struct BookPage: View {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text(header).font(Theme.kicker(11)).kerning(1.1).foregroundStyle(Theme.ink2).lineLimit(1)
                Spacer()
                Text(headerTrailing).font(Theme.ui(11)).foregroundStyle(Theme.ink2).lineLimit(1)
            }
            WordRun(spans: spans, currentIndex: currentIndex, font: Theme.serif(fontSize), color: Theme.ink, onTap: onTap, noted: noted)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .clipped()
            Spacer(minLength: 0)
            HStack {
                Text(footer).font(Theme.mono(11)).foregroundStyle(Theme.ink2)
                Spacer()
                Text(footerTrailing).font(Theme.mono(11)).foregroundStyle(Theme.ink2)
            }
        }
        .padding(.leading, edge == .leading ? 52 : 44)
        .padding(.trailing, edge == .leading ? 44 : 52)
        .padding(.top, 36)
        .padding(.bottom, 28)
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
        VStack(spacing: 14) {
            HStack(spacing: large ? 28 : 8) {
                Button { reader.skip(-15) } label: { Text("−15").font(Theme.mono(large ? 16 : 12)) }
                    .buttonStyle(PaperButtonStyle(size: large ? 72 : 44))
                    .accessibilityLabel("Back 15 seconds")
                Button {
                    if !reader.isSpeaking || reader.isPaused { engine.playReading(document) } else { reader.pause() }
                } label: {
                    Image(systemName: reader.isSpeaking && !reader.isPaused ? "pause.fill" : "play.fill")
                        .font(.system(size: large ? 34 : 18))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(PaperButtonStyle(size: large ? 112 : 44, filled: true))
                .accessibilityLabel(reader.isSpeaking && !reader.isPaused ? "Pause" : "Play")
                Button { reader.skip(15) } label: { Text("+15").font(Theme.mono(large ? 16 : 12)) }
                    .buttonStyle(PaperButtonStyle(size: large ? 72 : 44))
                    .accessibilityLabel("Forward 15 seconds")
                if !compact {
                    RateMenu()
                    Text(formatMinutesLeft(reader.secondsLeftInChapter))
                        .font(Theme.ui(12)).foregroundStyle(Theme.ink2)
                        .padding(.trailing, 10)
                        .lineLimit(1)
                }
            }
            .padding(6)
            .background(Capsule().fill(Theme.paper).overlay(Capsule().stroke(Theme.line, lineWidth: 1)))
            .shadow(color: Theme.ink.opacity(0.10), radius: 12, y: 6)

            if !compact {
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
                .font(Theme.ui(12, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 44, minHeight: 44)
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
            Image(systemName: holding ? "waveform" : "mic")
                .symbolEffect(.variableColor.iterative, isActive: holding)
            Text(holding ? "Saying a note… let go to keep" : "Hold to say a note")
                .lineLimit(1)
            if holding {
                Text(String(engine.recorder.transcript.plain.suffix(40)))
                    .font(Theme.serif(14))
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(1)
            }
        }
        .font(Theme.ui(large ? 16 : 13, weight: .medium))
        .foregroundStyle(holding ? .white : Theme.ribbonInk)
        .padding(.horizontal, 16)
        .frame(minHeight: large ? 64 : 44)
        .background(Capsule().fill(holding ? Theme.ribbon : Theme.card))
        .contentShape(Capsule())
        .animation(.snappy, value: holding)
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
                        .font(Theme.ui(15)).foregroundStyle(Theme.ink2)
                }
                ForEach(notes) { note in
                    Button {
                        engine.reader.goToChapter(note.chapterIndex)
                        engine.reader.currentIndex = note.spanIndex
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.text.isEmpty ? "(no words heard)" : note.text)
                                .font(Theme.serif(17)).foregroundStyle(Theme.ink)
                            Text("\(chapterTitle(note.chapterIndex)) · \(note.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(Theme.ui(12)).foregroundStyle(Theme.ink2)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Theme.paper)
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
            .paperBackground()
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Read my notes back", systemImage: "person.wave.2") {
                        engine.reader.speakNotes(notes, voice: engine.settings.personalVoice ?? engine.settings.voice)
                    }
                    .disabled(notes.isEmpty)
                }
            }
        }
    }

    private func chapterTitle(_ i: Int) -> String {
        document.chapters.indices.contains(i) ? document.chapters[i].title : "Chapter \(i + 1)"
    }
}
