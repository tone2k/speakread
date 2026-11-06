import SwiftUI
import UIKit

// MARK: - Tokens

/// Verso HUD design tokens. One saturated color: `signal`, identical in
/// both appearances. Every other token resolves per color scheme
/// (Tony's call, Nov 6): the dark values are the original HUD palette;
/// the light values are the same design language inverted — paper-white
/// ground, dark ink, same mono/chamfer/grid rules. Nightstand's red
/// lens does NOT adapt. Contrast values are WCAG 2.x ratios against the
/// mode's `bg0` unless noted.
enum HUD {
    /// A color that resolves dark/light by trait collection, so a
    /// single static token serves both appearances everywhere —
    /// including inside Canvas drawings.
    private static func dyn(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .light ? light : dark)
        })
    }

    // Ground
    static let bg0 = dyn(0x07090B, 0xF6F4EF)        // app ground
    static let bg1 = dyn(0x0D1117, 0xFFFFFF)        // panels, panes, transport, sheets
    static let bg2 = dyn(0x151B22, 0xEBE8E0)        // pressed, selected row, active seam channel
    static let grid = dyn(0x151C23, 0xE4E0D5)       // background grid (decorative)
    static let rule = dyn(0x26303A, 0xD9D4C7)       // panel borders, separators (decorative)
    static let ruleStrong = dyn(0x56636F, 0x8B8676) // interactive outlines (3.24:1 dark / ~3.4:1 light)

    // Text
    static let fg0 = dyn(0xE6EDF3, 0x16191D)        // primary, reading text (16.88:1 / ~15:1)
    static let fg1 = dyn(0x9BA7B4, 0x4B5563)        // secondary, read-past words (8.15:1 / ~7:1)
    static let fg2 = dyn(0x6E7A87, 0x5D6874)        // settling words, ticks (4.56:1 / ~5.4:1). Not on bg2.

    // Signal: the trace. The only saturated color — the same orange in both modes.
    static let signal = Color(hex: 0xFF5A1F)     // 6.40:1 on dark bg0
    static let signalInk = dyn(0xFF7A47, 0xC2410C)  // signal text <= 12 pt (7.72:1 / ~4.9:1)
    static let onSignal = Color(hex: 0x07090B)   // text on a signal fill (6.40:1)
    static let lockFill = signal.opacity(0.14)   // behind the current word; fg0 on it 14.75:1

    // Status (always with a text label)
    static let caution = dyn(0xF2B33D, 0x9A6B00)    // 10.72:1 / ~4.9:1
    static let ok = dyn(0x4FD69C, 0x0E7A4D)         // 10.86:1 / ~5.3:1

    /// Red-lens palette. Nightstand only.
    enum Night {
        static let bg = Color.black
        static let n0 = Color(hex: 0xE0391B)     // 4.77:1 on black
        static let n1 = Color(hex: 0xB8341A)     // 3.54:1 — only >= 18 pt, or >= 14 pt semibold
        static let n2 = Color(hex: 0x6A1E10)     // decorative only
    }

    enum Space {
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s5: CGFloat = 24
        static let s6: CGFloat = 32
        static let s7: CGFloat = 48
        static let s8: CGFloat = 64
        static let closedMargin: CGFloat = 20
        static let paneMargin: CGFloat = 32
        static let rowMinHeight: CGFloat = 56
        static let hitMin: CGFloat = 44
    }

    /// Chamfer size for a control or panel of a given height.
    static func chamfer(for size: CGFloat) -> CGFloat {
        size >= 84 ? 12 : size > 44 ? 8 : 4
    }

    /// SF Mono at a fixed size. Prefer `.hudText(_:)`, which scales with Dynamic Type.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Reading text. The caller scales `size` (user setting 14...30).
    static func read(_ size: CGFloat) -> Font { mono(size) }
    /// Extra line spacing for reading text: about 1.55 total line height in SF Mono.
    static func readLineSpacing(_ size: CGFloat) -> CGFloat { (size * 0.35).rounded() }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - Type scale

enum HUDTextStyle {
    case display0, display1, display2, title1, title2, title3, body, meta, label, micro

    var size: CGFloat {
        switch self {
        case .display0: 72
        case .display1: 56
        case .display2: 40
        case .title1: 28
        case .title2: 22
        case .title3: 17
        case .body: 15
        case .meta: 13
        case .label: 11
        case .micro: 9
        }
    }

    var weight: Font.Weight {
        switch self {
        case .display0, .display1, .display2, .title2, .title3, .micro: .medium
        case .title1, .label: .semibold
        case .body, .meta: .regular
        }
    }

    var tracking: CGFloat {
        switch self {
        case .display0: -2
        case .display1: -1.5
        case .display2: -1
        case .title1: 0.5
        case .label: 1.6
        case .micro: 1.2
        default: 0
        }
    }

    var uppercase: Bool { self == .title1 || self == .label || self == .micro }

    var relativeTo: UIFont.TextStyle {
        switch self {
        case .display0, .display1, .display2: .largeTitle
        case .title1: .title1
        case .title2: .title2
        case .title3: .headline
        case .body: .subheadline
        case .meta: .footnote
        case .label: .caption1
        case .micro: .caption2
        }
    }
}

private struct HUDTextModifier: ViewModifier {
    let style: HUDTextStyle
    var sizeOverride: CGFloat?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        let base = sizeOverride ?? style.size
        let size = UIFontMetrics(forTextStyle: style.relativeTo).scaledValue(for: base, compatibleWith: traits)
        content
            .font(HUD.mono(size, style.weight))
            .tracking(style.tracking)
            .textCase(style.uppercase ? .uppercase : nil)
    }
}

extension View {
    /// Applies a HUD type token, scaled for Dynamic Type.
    func hudText(_ style: HUDTextStyle, size: CGFloat? = nil) -> some View {
        modifier(HUDTextModifier(style: style, sizeOverride: size))
    }

    /// `bg0` ground, with the dither texture when `grid` is true. Never use it under reading text.
    func hudGround(grid: Bool = true) -> some View {
        background {
            if grid { DitherGround() } else { HUD.bg0.ignoresSafeArea() }
        }
    }
}

// MARK: - Dither ground

/// Sensor noise instead of a grid: a 1-bit dither at about 3 percent, one
/// device pixel per dot. The tile is drawn once per appearance and scale,
/// then tiled by the GPU, so the ground costs nothing per frame.
struct DitherGround: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var scale

    var body: some View {
        Image(uiImage: DitherTile.image(dark: scheme == .dark, scale: scale))
            .resizable(resizingMode: .tile)
            .background(HUD.bg0)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

@MainActor
enum DitherTile {
    private static var cache: [String: UIImage] = [:]
    static let points: CGFloat = 96

    static func image(dark: Bool, scale: CGFloat) -> UIImage {
        let key = "\(dark ? "d" : "l")-\(scale)"
        if let cached = cache[key] { return cached }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let side = Int(points * scale)
        let px = 1 / scale
        let image = UIGraphicsImageRenderer(size: CGSize(width: points, height: points), format: format).image { _ in
            (dark ? UIColor.white.withAlphaComponent(0.035) : UIColor.black.withAlphaComponent(0.05)).setFill()
            // A fixed-seed linear congruential generator: the same noise every launch.
            var state: UInt32 = 0x9E37_79B9
            for y in 0..<side {
                for x in 0..<side {
                    state = state &* 1_664_525 &+ 1_013_904_223
                    if (state >> 24) < 8 {
                        UIRectFill(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: px))
                    }
                }
            }
        }
        cache[key] = image
        return image
    }
}

// MARK: - Shapes

/// A rectangle with 45° cut corners. Default: top-trailing only.
/// Add `.flipsForRightToLeftLayoutDirection(true)` where it matters.
struct Chamfer: Shape {
    struct Corners: OptionSet {
        let rawValue: Int
        static let topLeading = Corners(rawValue: 1 << 0)
        static let topTrailing = Corners(rawValue: 1 << 1)
        static let bottomTrailing = Corners(rawValue: 1 << 2)
        static let bottomLeading = Corners(rawValue: 1 << 3)
    }

    var cut: CGFloat
    var corners: Corners = .topTrailing

    func path(in r: CGRect) -> Path {
        let c = min(cut, min(r.width, r.height) / 2)
        var p = Path()
        if corners.contains(.topLeading) {
            p.move(to: CGPoint(x: r.minX, y: r.minY + c))
            p.addLine(to: CGPoint(x: r.minX + c, y: r.minY))
        } else {
            p.move(to: CGPoint(x: r.minX, y: r.minY))
        }
        if corners.contains(.topTrailing) {
            p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
        } else {
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        }
        if corners.contains(.bottomTrailing) {
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
            p.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
        } else {
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        }
        if corners.contains(.bottomLeading) {
            p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY - c))
        } else {
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        }
        p.closeSubpath()
        return p
    }
}

/// Four L-shaped reticle corners. Stroke it: `.stroke(HUD.fg0, lineWidth: 1.5)`.
struct Brackets: Shape {
    var arm: CGFloat = 8

    func path(in r: CGRect) -> Path {
        let a = min(arm, min(r.width, r.height) / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + a)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + a, y: r.minY))
        p.move(to: CGPoint(x: r.maxX - a, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + a))
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - a)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - a, y: r.maxY))
        p.move(to: CGPoint(x: r.minX + a, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - a))
        return p
    }
}

// MARK: - Buttons

/// Outline control. `primary` = filled `fg0` (play). Pressed inverts, with no animation.
struct HUDButtonStyle: ButtonStyle {
    var size: CGFloat = 52
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        let filled = primary != configuration.isPressed
        let shape = Chamfer(cut: HUD.chamfer(for: size))
        return configuration.label
            .hudText(.label)
            .foregroundStyle(filled ? HUD.bg0 : HUD.fg0)
            .frame(minWidth: size, minHeight: size)
            .padding(.horizontal, HUD.Space.s2)
            .background(shape.fill(filled ? HUD.fg0 : HUD.bg0))
            .overlay(shape.stroke(HUD.ruleStrong, lineWidth: 1))
            .contentShape(shape)
    }
}

/// Record and stop. Square, `signal` fill, no shadow.
struct SignalButtonStyle: ButtonStyle {
    var size: CGFloat = 84

    func makeBody(configuration: Configuration) -> some View {
        let shape = Chamfer(cut: HUD.chamfer(for: size))
        return configuration.label
            .foregroundStyle(HUD.onSignal)
            .frame(width: size, height: size)
            .background(shape.fill(configuration.isPressed ? HUD.signalInk : HUD.signal))
            .contentShape(shape)
    }
}

// MARK: - Ground, seam, trace

/// 24 pt line grid, 1 px lines. Static: redraws only when its size changes.
struct GridGround: View {
    var spacing: CGFloat = 24
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { ctx, size in
            let w = 1 / displayScale
            var p = Path()
            var x: CGFloat = 0
            while x <= size.width { p.addRect(CGRect(x: x, y: 0, width: w, height: size.height)); x += spacing }
            var y: CGFloat = 0
            while y <= size.height { p.addRect(CGRect(x: 0, y: y, width: size.width, height: w)); y += spacing }
            ctx.fill(p, with: .color(HUD.grid))
        }
        .background(HUD.bg0)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Scanlines for panel header strips: 1 px every 3 pt, black at 18%.
struct Scanlines: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            var y: CGFloat = 0
            while y < size.height { p.addRect(CGRect(x: 0, y: y, width: size.width, height: 1 / displayScale)); y += 3 }
            ctx.fill(p, with: .color(.black.opacity(0.18)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Replaces `SpineGutter`. Edge rules, tick ruler, darker channel when the fold is active.
struct Seam: View {
    let axis: Axis
    let isActive: Bool

    var body: some View {
        Canvas { ctx, size in
            let vertical = axis == .vertical
            let edge = isActive ? HUD.ruleStrong : HUD.rule
            if isActive { ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(HUD.bg2)) }
            if vertical {
                ctx.fill(Path(CGRect(x: 0, y: 0, width: 1, height: size.height)), with: .color(edge))
                ctx.fill(Path(CGRect(x: size.width - 1, y: 0, width: 1, height: size.height)), with: .color(edge))
            } else {
                ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: 1)), with: .color(edge))
                ctx.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)), with: .color(edge))
            }
            let length = vertical ? size.height : size.width
            let mid = (vertical ? size.width : size.height) / 2
            var t: CGFloat = 24
            while t < length {
                let major = Int(t) % 96 == 0
                let tick: CGFloat = major ? (isActive ? 10 : 8) : 4
                let color = major ? (isActive ? HUD.fg2 : HUD.ruleStrong) : edge
                let rect = vertical
                    ? CGRect(x: mid - tick / 2, y: t, width: tick, height: 1)
                    : CGRect(x: t, y: mid - tick / 2, width: 1, height: tick)
                ctx.fill(Path(rect), with: .color(color))
                if major {
                    // The offset at the major tick, as a hex word: the ruler reads.
                    let label = Text(formatHex(Int(t), digits: 4)).font(HUD.mono(7)).foregroundStyle(HUD.fg2)
                    let at = vertical ? CGPoint(x: mid, y: t + 8) : CGPoint(x: t, y: mid - 10)
                    ctx.draw(label, at: at, anchor: .center)
                }
                t += 24
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The signal trace on a vertical seam: a line from the top to the current line, a square, and a stub
/// toward the page that holds the line. Set `lineMidY` only when the line changes.
/// For a page turn, set it inside `withTransaction(Transaction(animation: nil))`.
struct SeamTrace: View {
    var lineMidY: CGFloat?
    var stubLeading: Bool
    /// One character in the square, such as the speaker's initial in a dialogue.
    var glyph: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            if let y = lineMidY {
                let height = max(1, geo.size.height)
                let square: CGFloat = glyph == nil ? 6 : 14
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(HUD.signal)
                        .frame(width: 2, height: height)
                        .scaleEffect(x: 1, y: min(max(y / height, 0), 1), anchor: .top)
                    Rectangle()
                        .fill(HUD.signal)
                        .frame(width: square, height: square)
                        .overlay {
                            if let glyph {
                                Text(glyph).font(HUD.mono(9, .semibold)).foregroundStyle(HUD.onSignal)
                            }
                        }
                        .overlay {
                            Rectangle().fill(HUD.signal).frame(width: 12, height: 2).offset(x: stubLeading ? -(square / 2 + 6) : (square / 2 + 6))
                        }
                        .offset(y: y - square / 2)
                }
                .frame(width: geo.size.width, height: height, alignment: .top)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: y)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Data components

/// Replaces `RibbonWaveform`. One Canvas, no implicit animation. Redraws at the data rate.
struct ScopeView: View {
    let levels: [Float]
    var height: CGFloat = 72
    var paused = false

    var body: some View {
        Canvas { ctx, size in
            let n = levels.count
            let midY = size.height / 2
            ctx.fill(Path(CGRect(x: 0, y: midY - 0.5, width: size.width, height: 1)), with: .color(HUD.rule))
            guard n > 0 else { return }
            let barWidth: CGFloat = 3
            let step = barWidth + 2
            let startX = size.width - CGFloat(n) * step + 2
            let base = paused ? HUD.fg2 : HUD.signal
            for (i, level) in levels.enumerated() {
                let h = max(2, CGFloat(level) * size.height)
                let rect = CGRect(x: startX + CGFloat(i) * step, y: midY - h / 2, width: barWidth, height: h)
                let alpha = 0.35 + 0.65 * Double(i) / Double(max(1, n - 1))
                ctx.fill(Path(rect), with: .color(base.opacity(alpha)))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Leaf view: the only place that reads `recorder.levels`, so the parent body does not run at 20 Hz.
struct RecorderScope: View {
    let recorder: Recorder
    var height: CGFloat = 72

    var body: some View {
        ScopeView(levels: recorder.levels, height: height, paused: recorder.isPaused)
    }
}

/// `HUDTimeline` replaces `RibbonProgress`. Moving parts use transforms, not frame changes.
struct HUDTimeline: View {
    let progress: Double
    var ticks: [Double] = []
    var onSeek: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let p = min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Canvas { ctx, size in
                    ctx.fill(Path(CGRect(x: 0, y: size.height / 2 - 1, width: size.width, height: 2)), with: .color(HUD.rule))
                    for t in ticks {
                        ctx.fill(Path(CGRect(x: size.width * t, y: size.height / 2 + 4, width: 1, height: 6)), with: .color(HUD.fg1))
                    }
                }
                Rectangle()
                    .fill(HUD.signal)
                    .frame(width: w, height: 2)
                    .scaleEffect(x: p, y: 1, anchor: .leading)
                Rectangle()
                    .fill(HUD.signal)
                    .frame(width: 2, height: 16)
                    .offset(x: w * p - 1)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onEnded { value in
                    onSeek?(min(max(value.location.x / w, 0), 1))
                }
            )
        }
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

/// 20-cell progress bar for cartridges and rows.
struct CellBar: View {
    let progress: Double
    var cells = 20

    var body: some View {
        Canvas { ctx, size in
            let gap: CGFloat = 2
            let w = (size.width - gap * CGFloat(cells - 1)) / CGFloat(cells)
            let filled = Int((min(max(progress, 0), 1) * Double(cells)).rounded(.down))
            for i in 0..<cells {
                let r = CGRect(x: CGFloat(i) * (w + gap), y: 0, width: w, height: size.height)
                ctx.fill(Path(r), with: .color(i < filled ? HUD.signal : HUD.rule))
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("\(Int(progress * 100)) percent")
    }
}

/// Replaces `PulsingDot`. Steps twice a second instead of easing every frame.
struct BlinkDot: View {
    var color: Color = HUD.signal
    var size: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            dot(1)
        } else {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let on = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
                dot(on ? 1 : 0.25)
            }
        }
    }

    private func dot(_ opacity: Double) -> some View {
        Rectangle().fill(color).frame(width: size, height: size).opacity(opacity).accessibilityHidden(true)
    }
}

/// Replaces `kicker()` section labels.
struct PanelHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title).hudText(.label).foregroundStyle(HUD.fg1)
            Spacer()
            if let trailing { Text(trailing).hudText(.meta).foregroundStyle(HUD.fg1) }
        }
        .padding(.horizontal, HUD.Space.s4)
        .frame(height: 28)
        .background {
            ZStack {
                HUD.bg1
                Scanlines()
            }
        }
        .overlay(alignment: .bottom) { HUD.rule.frame(height: 1) }
    }
}

/// Segmented choice (spec 2a): bordered row of label segments; the
/// selected segment fills signal with onSignal text.
struct SegmentSwitch: View {
    let options: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                Button {
                    selection = index
                } label: {
                    Text(options[index])
                        .hudText(.label)
                        .foregroundStyle(selection == index ? HUD.onSignal : HUD.fg2)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(selection == index ? HUD.signal : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < options.count - 1 {
                    Rectangle().fill(HUD.rule).frame(width: 1, height: 28)
                }
            }
        }
        .overlay(Rectangle().strokeBorder(HUD.ruleStrong, lineWidth: 1))
        .fixedSize()
    }
}

/// The mini cartridge used inline (32×44 in the Listening header,
/// 44×60 in the Shelf continue panel): spine box + cell bar only.
struct CartridgeMini: View {
    var progress: Double = 0
    var width: CGFloat = 32
    var height: CGFloat = 44

    var body: some View {
        ZStack(alignment: .bottom) {
            HUD.bg1
            CellBar(progress: progress, cells: 8)
                .padding(3)
        }
        .frame(width: width, height: height)
        .overlay(Rectangle().strokeBorder(HUD.rule, lineWidth: 1))
    }
}

/// The live strip (was RibbonTab / ContinueCard / RecordingCard): a 2 pt
/// signal line over a 48 pt bg1 strip with a 3 pt signal leading bar.
struct TraceStrip: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(HUD.signal).frame(height: 2)
            HStack(spacing: 0) {
                Rectangle().fill(HUD.signal).frame(width: 3)
                Text(text)
                    .hudText(.meta)
                    .foregroundStyle(HUD.fg0)
                    .lineLimit(1)
                    .padding(.leading, 12)
                Spacer()
                Text("›")
                    .hudText(.title3)
                    .foregroundStyle(HUD.fg1)
                    .padding(.trailing, 12)
            }
            .frame(height: 48)
            .background(HUD.bg1)
            .overlay(alignment: .bottom) { Rectangle().fill(HUD.rule).frame(height: 1) }
        }
        .contentShape(Rectangle())
    }
}

/// One list row (was DocumentRow): title + readout, summary, meta line,
/// optional 20-cell progress bar under the meta for in-progress books.
struct DataRow: View {
    let title: String
    let trailing: String
    let summary: String
    let meta: String
    var progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).hudText(.title3).foregroundStyle(HUD.fg0).lineLimit(1)
                Spacer(minLength: 8)
                Text(trailing).hudText(.meta).foregroundStyle(HUD.fg1)
            }
            Text(summary).hudText(.body).foregroundStyle(HUD.fg1).lineLimit(1)
            Text(meta).hudText(.label).foregroundStyle(HUD.fg2).lineLimit(1)
            if let progress {
                CellBar(progress: progress, cells: 20)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: HUD.Space.rowMinHeight)
        .overlay(alignment: .top) { Rectangle().fill(HUD.rule).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

/// A book on the shelf (was BookCover): cell-wide, 196 pt tall, bg1,
/// 1 pt rule, 8 pt chamfer. The pattern band replaces the paper tints.
struct Cartridge: View {
    enum Pattern: Int, CaseIterable {
        case solid, grid, hatch, scanline
    }

    let title: String
    let meta: String
    let progress: Double
    let pattern: Pattern

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            patternBand
                .frame(height: 40)
            Text(title)
                .hudText(.title3)
                .foregroundStyle(HUD.fg0)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            Text(meta).hudText(.meta).foregroundStyle(HUD.fg1).lineLimit(1)
            HStack(spacing: 8) {
                CellBar(progress: progress, cells: 20)
                if progress > 0 {
                    Text(String(format: "%03d%%", Int(progress * 100)))
                        .hudText(.meta)
                        .foregroundStyle(HUD.fg1)
                }
            }
        }
        .padding(12)
        // The width is the grid cell's, never a fixed 150: a fixed width
        // inside narrower flexible columns is what piled the spread's
        // cartridges on top of each other, clipped the first card's
        // author line, and collided the progress bars.
        .frame(maxWidth: .infinity)
        .frame(height: 196)
        .background(HUD.bg1)
        .clipShape(Chamfer(cut: 8))
        .overlay(Chamfer(cut: 8).stroke(HUD.rule, lineWidth: 1))
    }

    @ViewBuilder private var patternBand: some View {
        switch pattern {
        case .solid:
            HUD.bg2
        case .grid:
            GridGround()
        case .hatch:
            Canvas { ctx, size in
                var path = Path()
                let step: CGFloat = 7
                var x = -size.height
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += step
                }
                ctx.stroke(path, with: .color(HUD.grid), lineWidth: 1)
            }
            .background(HUD.bg0)
        case .scanline:
            ZStack { HUD.bg0; Scanlines() }
        }
    }
}
