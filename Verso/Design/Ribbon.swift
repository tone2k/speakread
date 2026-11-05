import SwiftUI

/// A ribbon with a notched end, hanging down.
struct RibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let notch = rect.height * 0.12
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - notch))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// The ribbon hanging out of the top of the closed phone. Tap it to continue.
struct RibbonTab: View {
    var width: CGFloat = 22
    var height: CGFloat = 118
    var color: Color = Theme.ribbon

    var body: some View {
        RibbonShape()
            .fill(color)
            .frame(width: width, height: height)
            .shadow(color: Theme.ink.opacity(0.18), radius: 6, x: 2, y: 4)
    }
}

/// The ribbon as a waveform: one bar per recent level, newest on the trailing edge.
struct RibbonWaveform: View {
    let levels: [Float]
    var maxHeight: CGFloat = 72
    var color: Color = Theme.ribbon
    var showsEnd: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { i, level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(opacity(for: i)))
                    .frame(width: 4, height: max(5, CGFloat(level) * maxHeight))
            }
            if showsEnd {
                RibbonShape()
                    .fill(color)
                    .frame(width: 12, height: maxHeight + 12)
            }
        }
        .frame(height: maxHeight + 12)
        .animation(.linear(duration: 0.05), value: levels)
        .accessibilityHidden(true)
    }

    private func opacity(for index: Int) -> Double {
        let fraction = Double(index) / Double(max(1, levels.count - 1))
        return 0.35 + 0.65 * fraction
    }
}

/// The ribbon as a playhead across a progress line.
struct RibbonProgress: View {
    let progress: Double
    var color: Color = Theme.ribbon
    var track: Color = Theme.line
    var onSeek: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geo in
            let x = geo.size.width * min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(track).frame(height: 2)
                Capsule().fill(color).frame(width: x, height: 2)
                RibbonShape()
                    .fill(color)
                    .frame(width: 10, height: 26)
                    .offset(x: x - 5, y: -13)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        onSeek?(min(max(value.location.x / geo.size.width, 0), 1))
                    }
            )
        }
        .frame(height: 28)
    }
}

/// A small typographic book cover: a dark spine card with a progress line.
struct CoverThumb: View {
    let title: String
    var progress: Double = 0
    var width: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading) {
            Spacer()
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.nightInk.opacity(0.25)).frame(height: 2)
                Rectangle().fill(Theme.ribbon).frame(width: max(0, (width - 10) * progress), height: 2)
            }
        }
        .padding(5)
        .frame(width: width, height: width * 1.35)
        .background(RoundedRectangle(cornerRadius: 3).fill(Theme.ink))
        .accessibilityLabel(title)
    }
}
