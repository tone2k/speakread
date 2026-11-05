import SwiftUI

/// Lays out words left to right, wrapping like text, so each word can be tapped.
struct WordFlow: Layout {
    var lineSpacing: CGFloat = 6

    struct Cache {
        var sizes: [CGSize] = []
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? 10_000
        let frames = arrange(sizes: cache.sizes, width: width)
        let height = frames.last.map { $0.maxY } ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let frames = arrange(sizes: cache.sizes, width: bounds.width)
        for (i, subview) in subviews.enumerated() where i < frames.count {
            let f = frames[i]
            subview.place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
        }
    }

    private func arrange(sizes: [CGSize], width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        frames.reserveCapacity(sizes.count)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for size in sizes {
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width
            lineHeight = max(lineHeight, size.height)
        }
        return frames
    }
}

/// A run of spans drawn as tappable words, with the spoken word under the ribbon.
struct WordRun: View {
    let spans: ArraySlice<TimedSpan>
    let currentIndex: Int?
    var font: Font = Theme.serif(19)
    var color: Color = Theme.ink
    var dimBefore: Bool = false
    var onTap: ((Int) -> Void)?
    /// Spans that carry a margin note. They get a small red knot.
    var noted: Set<Int> = []

    var body: some View {
        WordFlow(lineSpacing: 6) {
            ForEach(spans) { span in
                Word(span: span, isCurrent: span.id == currentIndex, font: font, color: wordColor(span), hasNote: noted.contains(span.id))
                    .onTapGesture { onTap?(span.id) }
                    .accessibilityAddTraits(span.id == currentIndex ? [.isSelected] : [])
            }
        }
        .animation(.easeOut(duration: 0.12), value: currentIndex)
    }

    private func wordColor(_ span: TimedSpan) -> Color {
        if !span.isFinal { return Theme.ink3 }
        if span.confidence < 0.6 { return Theme.ink2 }
        if dimBefore, let currentIndex, span.id < currentIndex { return Theme.ink2 }
        return color
    }
}

struct Word: View {
    let span: TimedSpan
    let isCurrent: Bool
    let font: Font
    let color: Color
    var hasNote: Bool = false

    var body: some View {
        Text(span.text)
            .font(font)
            .foregroundStyle(color)
            .background(alignment: .bottomLeading) {
                if isCurrent {
                    Theme.ribbon.opacity(0.14)
                        .overlay(alignment: .bottom) { Theme.ribbon.frame(height: 2) }
                        .padding(.trailing, trailingSpace)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .topTrailing) {
                if hasNote {
                    Circle().fill(Theme.ribbon).frame(width: 6, height: 6).offset(x: -2, y: 2)
                }
            }
    }

    private var trailingSpace: CGFloat {
        span.text.hasSuffix(" ") ? 4 : 0
    }
}
