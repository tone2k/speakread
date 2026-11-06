import SwiftUI
import AVFoundation

/// Change the reading voice without leaving the book. One list, one
/// active selection: every row's checkmark derives from
/// `Settings.voiceSelection`, and every tap goes through Engine's
/// selection funnel — so a pick here and a pick in Settings can never
/// disagree, and mid-playback the new voice takes over at the current
/// sentence with the position untouched.
struct VoicePickerSheet: View {
    @Environment(Engine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @State private var appleVoices: [AVSpeechSynthesisVoice] = []
    private let kokoro = KokoroVoice.shared

    private var settings: Settings { engine.settings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader(title: "VOICE", trailing: "ONE ACTIVE VOICE")

                groupLabel("KOKORO · ON-DEVICE")
                if kokoro.modelState != .ready {
                    Text("MODEL NOT DOWNLOADED · APPLE VOICES READ UNTIL IT IS · GET IT IN SETTINGS → EARS & VOICE")
                        .hudText(.label)
                        .foregroundStyle(HUD.caution)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
                ForEach(KokoroVoice.englishVoices, id: \.id) { voice in
                    row(title: voice.name, subtitle: "Kokoro · \(voice.detail)", selected: settings.voiceSelection == .kokoro(voice.id)) {
                        engine.selectKokoroVoice(voice.id)
                        dismiss()
                    }
                }

                if let personal = personalVoice {
                    groupLabel("YOURS")
                    row(title: "Your Voice", subtitle: "Your own voice · on this iPhone", selected: settings.voiceSelection == .apple(personal.identifier)) {
                        Task { await pickPersonalVoice(personal) }
                    }
                }

                groupLabel("APPLE")
                ForEach(stockVoices, id: \.identifier) { voice in
                    row(title: voice.name, subtitle: subtitle(voice), selected: settings.voiceSelection == .apple(voice.identifier)) {
                        engine.selectAppleVoice(voice)
                        dismiss()
                    }
                }

                Text("A NEW VOICE STARTS AT THE CURRENT SENTENCE · YOUR PLACE IS KEPT")
                    .hudText(.label)
                    .foregroundStyle(HUD.fg2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
            .background(HUD.bg1)
            .overlay(Rectangle().strokeBorder(HUD.rule, lineWidth: 1))
            .padding(.horizontal, HUD.Space.closedMargin)
            .padding(.vertical, 24)
        }
        .hudGround(grid: true)
        .task {
            appleVoices = SettingsView.voicesForCurrentLanguage()
            kokoro.refreshState()
        }
    }

    private var personalVoice: AVSpeechSynthesisVoice? {
        appleVoices.first { $0.voiceTraits.contains(.isPersonalVoice) }
    }

    private var stockVoices: [AVSpeechSynthesisVoice] {
        appleVoices.filter { !$0.voiceTraits.contains(.isPersonalVoice) }
    }

    /// Same authorization dance as the Settings row: if the voice exists
    /// but Verso isn't allowed yet, ask — then select on success.
    private func pickPersonalVoice(_ voice: AVSpeechSynthesisVoice) async {
        if AVSpeechSynthesizer.personalVoiceAuthorizationStatus != .authorized {
            let status = await AVSpeechSynthesizer.requestPersonalVoiceAuthorization()
            guard status == .authorized else { return }
        }
        engine.selectAppleVoice(voice)
        dismiss()
    }

    private func groupLabel(_ title: String) -> some View {
        Text(title)
            .hudText(.label)
            .foregroundStyle(HUD.fg2)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 2)
    }

    private func subtitle(_ voice: AVSpeechSynthesisVoice) -> String {
        var parts: [String] = []
        switch voice.quality {
        case .premium: parts.append("Premium")
        case .enhanced: parts.append("Enhanced")
        default: parts.append("Compact")
        }
        parts.append(Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language)
        return parts.joined(separator: " · ")
    }

    private func row(title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Rectangle().strokeBorder(HUD.ruleStrong, lineWidth: 1)
                        .frame(width: 14, height: 14)
                    if selected {
                        Rectangle().fill(HUD.signal).frame(width: 8, height: 8)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).hudText(.title3).foregroundStyle(HUD.fg0)
                    Text(subtitle).hudText(.meta).foregroundStyle(HUD.fg1)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(selected ? HUD.bg2 : Color.clear)
            .overlay(alignment: .leading) { Rectangle().fill(selected ? HUD.signal : Color.clear).frame(width: 2) }
            .overlay(alignment: .top) { Rectangle().fill(HUD.rule).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
