import SwiftUI

/// Ink on paper, one red ribbon.
enum Theme {
    static let paper = Color(red: 0.969, green: 0.957, blue: 0.933)      // F7F4EE
    static let card = Color(red: 0.929, green: 0.910, blue: 0.871)       // EDE8DE
    static let line = Color(red: 0.851, green: 0.824, blue: 0.769)       // D9D2C4
    static let ink = Color(red: 0.106, green: 0.098, blue: 0.082)        // 1B1915
    static let ink2 = Color(red: 0.353, green: 0.333, blue: 0.294)       // 5A554B
    static let ink3 = Color(red: 0.659, green: 0.635, blue: 0.584)       // A8A295
    static let ribbon = Color(red: 0.780, green: 0.196, blue: 0.122)     // C7321F
    static let ribbonInk = Color(red: 0.620, green: 0.149, blue: 0.086)  // 9E2616
    static let night = Color(red: 0.059, green: 0.055, blue: 0.047)      // 0F0E0C
    static let nightInk = Color(red: 0.910, green: 0.886, blue: 0.835)   // E8E2D5
    static let ember = Color(red: 0.949, green: 0.376, blue: 0.247)      // F2603F

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func kicker(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .semibold)
    }
}

extension View {
    /// Small caps label above a section.
    func kicker() -> some View {
        self
            .font(Theme.kicker())
            .textCase(.uppercase)
            .kerning(0.9)
            .foregroundStyle(Theme.ink2)
    }

    func paperBackground() -> some View {
        self.background(Theme.paper.ignoresSafeArea())
    }
}

/// A round button on paper.
struct PaperButtonStyle: ButtonStyle {
    var size: CGFloat = 52
    var filled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.ui(15, weight: .medium))
            .foregroundStyle(filled ? Theme.paper : Theme.ink)
            .frame(minWidth: size, minHeight: size)
            .padding(.horizontal, 6)
            .background(
                Capsule().fill(filled ? Theme.ink : Theme.paper)
                    .overlay(Capsule().stroke(Theme.line, lineWidth: filled ? 0 : 1))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The big red record or stop button.
struct RibbonButtonStyle: ButtonStyle {
    var size: CGFloat = 84

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.ribbon))
            .shadow(color: Theme.ribbon.opacity(0.35), radius: 12, y: 8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
