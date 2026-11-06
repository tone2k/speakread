import SwiftUI
import AVFoundation

/// Two plain questions: what turns speech into text, and what reads text aloud.
struct SettingsView: View {
    @Environment(Engine.self) private var engine
    @State private var voices: [AVSpeechSynthesisVoice] = []
    @State private var personalStatus: AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus = .notDetermined
    @State private var hasPersonalVoice = false
    @State private var showsPersonalVoiceGuide = false
    private let kokoro = KokoroVoice.shared

    private var settings: Settings { engine.settings }

    var body: some View {
        let selectedVoiceID = settings.voiceIdentifier ?? Reader.bestDefaultVoice()?.identifier
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Ears & Voice")
                    .hudText(.title1)
                    .foregroundStyle(HUD.fg0)

                section("APPEARANCE") {
                    HStack {
                        Text("THEME")
                            .hudText(.label)
                            .foregroundStyle(HUD.fg1)
                        Spacer()
                        SegmentSwitch(options: ["SYSTEM", "LIGHT", "DARK"], selection: appearanceSelection)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                section("EARS · SPEECH TO TEXT") {
                    ForEach(Settings.EarsChoice.allCases) { choice in
                        row(title: choice.title, subtitle: choice.subtitle, selected: settings.ears == choice) {
                            settings.ears = choice
                        }
                    }
                }

                section("VOICE · TEXT TO SPEECH") {
                    ForEach(Settings.VoiceEngineChoice.allCases) { choice in
                        row(title: choice.title, subtitle: choice.subtitle, selected: settings.voiceEngine == choice) {
                            settings.voiceEngine = choice
                            engine.reader.voiceEngine = choice
                        }
                    }
                    if settings.voiceEngine == .kokoro {
                        kokoroControls
                    }
                    if !hasNaturalVoice {
                        voiceDownloadHint
                    }
                    ForEach(voiceGroups, id: \.title) { group in
                        Text("\(group.title.uppercased()) · \(group.voices.count)")
                            .hudText(.label)
                            .foregroundStyle(HUD.fg2)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 2)
                        ForEach(group.voices, id: \.identifier) { voice in
                            row(title: voice.name, subtitle: voiceSubtitle(voice), selected: selectedVoiceID == voice.identifier) {
                                settings.voiceIdentifier = voice.identifier
                                engine.reader.voice = voice
                            }
                        }
                    }
                    personalVoiceRow
                    HStack {
                        Text("SPEED")
                            .hudText(.label)
                            .foregroundStyle(HUD.fg1)
                        Spacer()
                        SegmentSwitch(options: ["0.8×", "1.0×", "1.2×", "1.5×", "2.0×"], selection: speedSelection)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) { Rectangle().fill(HUD.rule).frame(height: 1) }
                }

                section("NIGHTSTAND") {
                    HStack {
                        Text("SLEEP TIMER")
                            .hudText(.label)
                            .foregroundStyle(HUD.fg1)
                        Spacer()
                        SegmentSwitch(options: ["5", "15", "30", "45"], selection: sleepSelection)
                        Text("MIN")
                            .hudText(.meta)
                            .foregroundStyle(HUD.fg1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                section("SIRI") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("“Hey Siri, start Verso”")
                            .hudText(.title3)
                            .foregroundStyle(HUD.fg0)
                        Text("Starts a recording from any pose. Siri learns the phrase the first time you open Verso.")
                            .hudText(.meta)
                            .foregroundStyle(HUD.fg1)
                    }
                    .padding(16)
                }

                HStack(spacing: 8) {
                    Image(systemName: "lock")
                    Text("LOCAL ONLY · NO ACCOUNT · NO UPLOAD")
                }
                .hudText(.label)
                .foregroundStyle(HUD.fg1)
                .padding(.top, 8)
            }
            .padding(.horizontal, HUD.Space.closedMargin)
            .padding(.vertical, 24)
        }
        .hudGround(grid: true)
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .task {
            voices = Self.voicesForCurrentLanguage()
            personalStatus = AVSpeechSynthesizer.personalVoiceAuthorizationStatus
            hasPersonalVoice = voices.contains { $0.voiceTraits.contains(.isPersonalVoice) }
            kokoro.refreshState()
            engine.reader.voiceEngine = settings.voiceEngine
            engine.reader.kokoroVoiceID = settings.kokoroVoice
        }
        .alert("Create your Personal Voice", isPresented: $showsPersonalVoiceGuide) {
            Button("Open Settings") { openAppSettings() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Personal Voices are created in the Settings app: Accessibility → Personal Voice → Create a Personal Voice. Record the phrases it asks for, then come back here and tap this row to use it.")
        }
    }

    // MARK: Pieces

    private static let speeds: [Double] = [0.8, 1.0, 1.2, 1.5, 2.0]
    private static let sleeps: [Int] = [5, 15, 30, 45]

    private var appearanceSelection: Binding<Int> {
        Binding(
            get: { Settings.AppearanceChoice.allCases.firstIndex(of: settings.appearance) ?? 0 },
            set: { index in settings.appearance = Settings.AppearanceChoice.allCases[index] }
        )
    }

    private var speedSelection: Binding<Int> {
        Binding(
            get: { Self.speeds.firstIndex(of: settings.rateMultiplier) ?? 1 },
            set: { index in
                let rate = Self.speeds[index]
                settings.rateMultiplier = rate
                engine.reader.setRate(rate)
            }
        )
    }

    private var sleepSelection: Binding<Int> {
        Binding(
            get: { Self.sleeps.firstIndex(of: settings.sleepMinutes) ?? 1 },
            set: { index in settings.sleepMinutes = Self.sleeps[index] }
        )
    }

    /// Voices grouped best-first: Premium, then Enhanced. Compact voices are
    /// never offered. Only tiers installed on this device get a group.
    private var voiceGroups: [(title: String, voices: [AVSpeechSynthesisVoice])] {
        let tiers: [(String, AVSpeechSynthesisVoiceQuality)] = [("Premium", .premium), ("Enhanced", .enhanced)]
        return tiers.compactMap { title, quality in
            let inTier = voices.filter { $0.quality == quality }
            return inTier.isEmpty ? nil : (title, inTier)
        }
    }

    private var hasNaturalVoice: Bool {
        voices.contains { $0.quality == .premium || $0.quality == .enhanced }
    }

    private var voiceDownloadHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("⚠ COMPACT VOICES ONLY")
                .hudText(.label)
                .foregroundStyle(HUD.caution)
            Text("Only the compact voices are on this iPhone")
                .hudText(.title3)
                .foregroundStyle(HUD.fg0)
            Text("Compact voices are the robotic ones. For a natural read, download an Enhanced or Premium voice in Settings → Accessibility → Spoken Content → Voices → English, then pick it here.")
                .hudText(.meta)
                .foregroundStyle(HUD.fg1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().strokeBorder(HUD.caution.opacity(0.6), lineWidth: 1))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(title: title)
            content()
        }
        .background(HUD.bg1)
        .overlay(Rectangle().strokeBorder(HUD.rule, lineWidth: 1))
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

    /// The Kokoro block inside the Voice section: a one-time model
    /// download, then the voice list. Apple's voices stay below as the
    /// fallback the reader returns to whenever Kokoro can't speak.
    @ViewBuilder
    private var kokoroControls: some View {
        switch kokoro.modelState {
        case .notDownloaded:
            kokoroDownloadRow(detail: "KOKORO MODEL · ~150 MB · ON-DEVICE", fault: nil)
        case .failed(let message):
            kokoroDownloadRow(detail: "KOKORO MODEL · ~150 MB · ON-DEVICE", fault: message)
        case .downloading:
            KokoroDownloadingRow()
        case .ready:
            HStack(spacing: 10) {
                Text("■ READY")
                    .hudText(.label)
                    .foregroundStyle(HUD.ok)
                Text("KOKORO MODEL · ON-DEVICE")
                    .hudText(.meta)
                    .foregroundStyle(HUD.fg1)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(alignment: .top) { Rectangle().fill(HUD.rule).frame(height: 1) }
            ForEach(KokoroVoice.englishVoices, id: \.id) { voice in
                row(title: voice.name, subtitle: "Kokoro · \(voice.detail)", selected: settings.kokoroVoice == voice.id) {
                    settings.kokoroVoice = voice.id
                    engine.reader.kokoroVoiceID = voice.id
                    Task { await kokoro.preload(voice: voice.id) }
                }
            }
        }
    }

    private func kokoroDownloadRow(detail: String, fault: String?) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Kokoro voice model").hudText(.title3).foregroundStyle(HUD.fg0)
                Text(detail).hudText(.meta).foregroundStyle(HUD.fg1)
                if let fault {
                    Text("FAULT · \(fault)")
                        .hudText(.label)
                        .foregroundStyle(HUD.caution)
                }
            }
            Spacer()
            Button(fault == nil ? "DOWNLOAD" : "RETRY") {
                Task { await kokoro.downloadModels(voice: settings.kokoroVoice) }
            }
            .buttonStyle(HUDButtonStyle(size: 44))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(HUD.rule).frame(height: 1) }
    }

    /// The Personal Voice row does the right thing in every state:
    /// - not yet authorized: tapping runs the real authorization request
    ///   (and selects the voice immediately if one already exists).
    /// - authorized, a personal voice exists: tapping selects it as the
    ///   reading voice; notes already read back in it.
    /// - authorized, none exists: tapping explains and offers Settings —
    ///   iOS keeps creation at Accessibility → Personal Voice; there is
    ///   no in-app creation API.
    /// - denied: tapping opens Settings so it can be allowed.
    private var personalVoiceRow: some View {
        Button {
            Task { await personalVoiceTapped() }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Rectangle().strokeBorder(HUD.ruleStrong, lineWidth: 1)
                        .frame(width: 14, height: 14)
                    if personalVoiceSelected {
                        Rectangle().fill(HUD.signal).frame(width: 8, height: 8)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Personal Voice").hudText(.title3).foregroundStyle(HUD.fg0)
                    Text(personalSubtitle).hudText(.meta).foregroundStyle(HUD.fg1)
                }
                Spacer()
                Text(personalActionLabel)
                    .hudText(.label)
                    .foregroundStyle(HUD.signalInk)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(personalVoiceSelected ? HUD.bg2 : Color.clear)
            .overlay(alignment: .leading) { Rectangle().fill(personalVoiceSelected ? HUD.signal : Color.clear).frame(width: 2) }
            .overlay(alignment: .top) { Rectangle().fill(HUD.rule).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(personalVoiceSelected ? [.isSelected] : [])
    }

    private var personalVoiceSelected: Bool {
        guard let pv = settings.personalVoice else { return false }
        return settings.voiceIdentifier == pv.identifier
    }

    private var personalActionLabel: String {
        switch personalStatus {
        case .authorized: return hasPersonalVoice ? (personalVoiceSelected ? "IN USE" : "USE IT") : "CREATE"
        case .denied: return "OPEN SETTINGS"
        case .unsupported: return ""
        default: return "ALLOW"
        }
    }

    private func personalVoiceTapped() async {
        switch personalStatus {
        case .authorized:
            if let pv = settings.personalVoice {
                settings.voiceIdentifier = pv.identifier
                engine.reader.voice = pv
            } else {
                showsPersonalVoiceGuide = true
            }
        case .denied:
            openAppSettings()
        case .unsupported:
            break
        default:
            personalStatus = await AVSpeechSynthesizer.requestPersonalVoiceAuthorization()
            voices = Self.voicesForCurrentLanguage()
            hasPersonalVoice = voices.contains { $0.voiceTraits.contains(.isPersonalVoice) }
            if personalStatus == .authorized, let pv = settings.personalVoice {
                settings.voiceIdentifier = pv.identifier
                engine.reader.voice = pv
            }
        }
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private var personalSubtitle: String {
        switch personalStatus {
        case .authorized:
            if !hasPersonalVoice { return "None on this iPhone yet · tap CREATE — iOS makes it in Settings → Accessibility → Personal Voice" }
            return personalVoiceSelected ? "In use · books and notes read in your own voice" : "On this iPhone · tap to read books and notes in your own voice"
        case .denied: return "Not allowed · tap to open Settings and allow Personal Voice"
        case .unsupported: return "Not available on this device"
        default: return "Hear books and notes read back in your own voice · tap ALLOW"
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

    /// The ten best natural voices on the phone, plus the Personal Voice if
    /// there is one (it has its own row). Compact voices are never offered.
    static func voicesForCurrentLanguage() -> [AVSpeechSynthesisVoice] {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        let personal = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix(code) && $0.voiceTraits.contains(.isPersonalVoice)
        }
        return Reader.castableVoices() + personal
    }
}

/// While the model downloads: an elapsed readout, no spinner (spec 2a).
/// The clock starts when this row appears, which is when the state flips.
struct KokoroDownloadingRow: View {
    @State private var startedAt = Date.now

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kokoro voice model").hudText(.title3).foregroundStyle(HUD.fg0)
                    Text("DOWNLOADING · \(formatTimecode(context.date.timeIntervalSince(startedAt)))")
                        .hudText(.meta)
                        .foregroundStyle(HUD.fg1)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .overlay(alignment: .top) { Rectangle().fill(HUD.rule).frame(height: 1) }
    }
}

extension Settings {
    /// The user's Personal Voice, if they made one and allowed Verso to use it.
    var personalVoice: AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices().first { $0.voiceTraits.contains(.isPersonalVoice) }
    }
}
