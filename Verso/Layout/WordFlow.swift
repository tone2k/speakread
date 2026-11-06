import SwiftUI

/// Size key for one word. The highlight never changes a word's size, so a size is measured
/// once per (span id, text, font size) and reused on every later update.
struct MeasureKey: LayoutValueKey {
    static let defaultValue = 0
}

extension TimedSpan {
    func measureKey(fontSize: CGFloat) -> Int {
        var h = Hasher()
        h.combine(id)
        h.combine(text)
        h.combine(Int(fontSize * 4))
        return h.finalize()
    }
}

/// Lays out words left to right, wrapping like text, so each word can be tapped.
/// P1 fix: measures only words whose key is new, and keeps frames until the keys or the width change.
struct WordFlow: Layout {
    var lineSpacing: CGFloat = 6

    struct Cache {
        var sizes: [Int: CGSize] = [:]
        var keys: [Int] = []
        var width: CGFloat = -1
        var frames: [CGRect] = []
    }

    func makeCache(subviews: Subviews) -> Cache {
        var cache = Cache()
        updateCache(&cache, subviews: subviews)
        return cache
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        let keys = subviews.map { $0[MeasureKey.self] }
        // A highlight-only update: same words, same sizes. No work.
        guard keys != cache.keys else { return }
        for (key, subview) in zip(keys, subviews) where cache.sizes[key] == nil {
            cache.sizes[key] = subview.sizeThatFits(.unspecified)
        }
        if cache.sizes.count > max(512, keys.count * 4) {
            let live = Set(keys)
            cache.sizes = cache.sizes.filter { live.contains($0.key) }
        }
        cache.keys = keys
        cache.width = -1
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? 10_000
        let frames = layoutFrames(&cache, width: width)
        return CGSize(width: width, height: frames.last?.maxY ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let frames = layoutFrames(&cache, width: bounds.width)
        for (i, subview) in subviews.enumerated() where i < frames.count {
            let f = frames[i]
            subview.place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
        }
    }

    private func layoutFrames(_ cache: inout Cache, width: CGFloat) -> [CGRect] {
        if cache.width == width, cache.frames.count == cache.keys.count { return cache.frames }
        var frames: [CGRect] = []
        frames.reserveCapacity(cache.keys.count)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for key in cache.keys {
            let size = cache.sizes[key] ?? .zero
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width
            lineHeight = max(lineHeight, size.height)
        }
        cache.frames = frames
        cache.width = width
        return frames
    }
}

/// A run of spans drawn as tappable words, with the lock under the spoken word.
/// Keep this for short runs only (Listening window, live recording tail). Long text uses the
/// TextKit view from finding P5.
///
/// Call-site change: pass `fontSize:` (a CGFloat) instead of `font:`.
struct WordRun: View {
    let spans: ArraySlice<TimedSpan>
    let currentIndex: Int?
    var fontSize: CGFloat = 19
    var color: Color = HUD.fg0
    var dimBefore: Bool = false
    var onTap: ((Int) -> Void)?
    /// Spans that carry a margin note. They get a small signal square.
    var noted: Set<Int> = []

    var body: some View {
        WordRunContent(spans: spans, currentIndex: currentIndex, fontSize: fontSize, color: color,
                       dimBefore: dimBefore, noted: noted, onTap: onTap)
            .equatable()
    }
}

/// The real body. `Equatable` so a parent re-render with the same inputs does nothing.
/// `onTap` is left out of `==` on purpose: closures never compare equal.
private struct WordRunContent: View, Equatable {
    let spans: ArraySlice<TimedSpan>
    let currentIndex: Int?
    let fontSize: CGFloat
    let color: Color
    let dimBefore: Bool
    let noted: Set<Int>
    let onTap: ((Int) -> Void)?

    static func == (l: Self, r: Self) -> Bool {
        l.currentIndex == r.currentIndex
            && l.fontSize == r.fontSize
            && l.dimBefore == r.dimBefore
            && l.color == r.color
            && l.noted == r.noted
            && l.spans == r.spans   // fast when string storage is shared, which it is between ticks
    }

    var body: some View {
        let font = HUD.read(fontSize)
        let space = fontSize * 0.6   // SF Mono advance
        WordFlow(lineSpacing: HUD.readLineSpacing(fontSize)) {
            ForEach(spans) { span in
                Word(span: span, isCurrent: span.id == currentIndex, font: font, color: wordColor(span),
                     hasNote: noted.contains(span.id), trailingSpace: span.text.hasSuffix(" ") ? space : 0)
                    .layoutValue(key: MeasureKey.self, value: span.measureKey(fontSize: fontSize))
                    .onTapGesture { onTap?(span.id) }
                    .accessibilityAddTraits(span.id == currentIndex ? [.isSelected] : [])
            }
        }
    }

    private func wordColor(_ span: TimedSpan) -> Color {
        if !span.isFinal { return HUD.fg2 }
        if span.confidence < 0.6 { return HUD.fg1 }
        if dimBefore, let currentIndex, span.id < currentIndex { return HUD.fg1 }
        return color
    }
}

struct Word: View {
    let span: TimedSpan
    let isCurrent: Bool
    let font: Font
    let color: Color
    var hasNote: Bool = false
    var trailingSpace: CGFloat = 0

    var body: some View {
        Text(span.text)
            .font(font)
            .foregroundStyle(color)
            .background(alignment: .bottomLeading) {
                if isCurrent {
                    HUD.lockFill
                        .overlay(alignment: .bottom) { HUD.signal.frame(height: 2) }
                        .padding(.trailing, trailingSpace)
                }
            }
            .overlay(alignment: .topTrailing) {
                if hasNote {
                    Rectangle().fill(HUD.signal).frame(width: 5, height: 5).offset(x: -2, y: 2)
                }
            }
    }
}
