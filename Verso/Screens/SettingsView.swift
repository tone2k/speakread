import SwiftUI
import AVFoundation

/// Two plain questions: what turns speech into text, and what reads text aloud.
struct SettingsView: View {
    @Environment(Engine.self) private var engine
    @State private var voices: [AVSpeechSynthesisVoice] = []
    @State private var personalStatus: AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus = .notDetermined

    private var settings: Settings { engine.settings }

    var body: some View {
        @Bindable var settings = engine.settings
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Ears & Voice").font(Theme.serif(32, weight: .medium)).foregroundStyle(Theme.ink)

                section("Ears · turns what you say into text") {
                    ForEach(Settings.EarsChoice.allCases) { choice in
                        row(title: choice.title, subtitle: choice.subtitle, selected: settings.ears == choice) {
                            settings.ears = choice
                        }
                    }
                }

                section("Voice · reads text aloud") {
                    ForEach(voices, id: \.identifier) { voice in
                        row(title: voice.name, subtitle: voiceSubtitle(voice), selected: (settings.voiceIdentifier ?? Reader.bestDefaultVoice()?.identifier) == voice.identifier) {
                            settings.voiceIdentifier = voice.identifier
                            engine.reader.voice = voice
                        }
                    }
                    personalVoiceRow
                    HStack {
                        Text("Speed").font(Theme.ui(16, weight: .medium)).foregroundStyle(Theme.ink)
                        Spacer()
                        Picker("Speed", selection: $settings.rateMultiplier) {
                            ForEach([0.8, 1.0, 1.2, 1.5, 2.0], id: \.self) { r in
                                Text(String(format: "%.1f×", r)).tag(r)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: settings.rateMultiplier) { _, new in engine.reader.setRate(new) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                section("Nightstand") {
                    HStack {
                        Text("Sleep timer").font(Theme.ui(16, weight: .medium)).foregroundStyle(Theme.ink)
                        Spacer()
                        Picker("Sleep timer", selection: $settings.sleepMinutes) {
                            ForEach([5, 15, 30, 45], id: \.self) { m in Text("\(m) min").tag(m) }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                section("Siri") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("“Hey Siri, start Verso”").font(Theme.ui(16, weight: .medium)).foregroundStyle(Theme.ink)
                        Text("Starts a recording from any pose. Siri learns the phrase the first time you open Verso.")
                            .font(Theme.ui(12)).foregroundStyle(Theme.ink2)
                    }
                    .padding(16)
                }

                HStack(spacing: 8) {
                    Image(systemName: "lock")
                    Text("Everything stays on this iPhone. No account, no upload.")
                }
                .font(Theme.ui(12)).foregroundStyle(Theme.ink2)
                .padding(.top, 8)
            }
            .padding(24)
        }
        .paperBackground()
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .task {
            voices = Self.voicesForCurrentLanguage()
            personalStatus = AVSpeechSynthesizer.personalVoiceAuthorizationStatus
        }
    }

    // MARK: Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).kicker()
            VStack(spacing: 0) { content() }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func row(title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.ui(16, weight: .medium)).foregroundStyle(Theme.ink)
                    Text(subtitle).font(Theme.ui(12)).foregroundStyle(Theme.ink2)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ribbon)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Rectangle().fill(Theme.ink.opacity(0.07)).frame(height: 1) }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var personalVoiceRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your Personal Voice").font(Theme.ui(16, weight: .medium)).foregroundStyle(Theme.ink)
                Text(personalSubtitle).font(Theme.ui(12)).foregroundStyle(Theme.ink2)
            }
            Spacer()
            if personalStatus != .authorized {
                Button("Allow") {
                    Task {
                        personalStatus = await AVSpeechSynthesizer.requestPersonalVoiceAuthorization()
                        voices = Self.voicesForCurrentLanguage()
                    }
                }
                .font(Theme.ui(13, weight: .semibold))
                .foregroundStyle(Theme.ribbonInk)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .overlay(alignment: .top) { Rectangle().fill(Theme.ink.opacity(0.07)).frame(height: 1) }
    }

    private var personalSubtitle: String {
        switch personalStatus {
        case .authorized:
            return settings.personalVoice == nil ? "Allowed · create one in Settings › Accessibility › Personal Voice" : "Reads your notes back in your own voice"
        case .denied: return "Not allowed · change it in Settings › Accessibility › Personal Voice"
        case .unsupported: return "Not available on this device"
        default: return "Hear your notes read back in your own voice"
        }
    }

    private func voiceSubtitle(_ voice: AVSpeechSynthesisVoice) -> String {
        var parts: [String] = []
        switch voice.quality {
        case .premium: parts.append("Premium")
        case .enhanced: parts.append("Enhanced")
        default: parts.append("Compact")
        }
        parts.append(Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language)
        if voice.voiceTraits.contains(.isPersonalVoice) { parts.append("Personal Voice") }
        return parts.joined(separator: " · ")
    }

    static func voicesForCurrentLanguage() -> [AVSpeechSynthesisVoice] {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(code) && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { a, b in
                if a.quality != b.quality { return a.quality.rawValue > b.quality.rawValue }
                return a.name < b.name
            }
    }
}

extension Settings {
    /// The user's Personal Voice, if they made one and allowed Verso to use it.
    var personalVoice: AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices().first { $0.voiceTraits.contains(.isPersonalVoice) }
    }
}
