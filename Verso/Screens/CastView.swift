import SwiftUI
import AVFoundation

/// The speaker of the current turn, as a small label above the text.
struct SpeakerKicker: View {
    let name: String

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(HUD.signal).frame(width: 6, height: 6)
            Text(name.uppercased())
                .hudText(.label)
                .foregroundStyle(HUD.signalInk)
                .lineLimit(1)
        }
        .accessibilityLabel("\(name) is speaking")
    }
}

/// The cast as a row of name cards. The card of whoever is speaking lights.
/// Tap a card to jump to that character's next line.
struct CastStrip: View {
    @Environment(Engine.self) private var engine

    private var reader: Reader { engine.reader }

    var body: some View {
        let members = (reader.cast?.members ?? []).filter { !$0.isNarrator }
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(members) { member in
                    let live = member.id == reader.currentSpeaker
                    Button {
                        reader.jumpToNextTurn(of: member.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(member.name.uppercased())
                                .hudText(.label)
                                .foregroundStyle(live ? HUD.onSignal : HUD.fg0)
                                .lineLimit(1)
                            Text(CastSheet.voiceName(for: member, engine: engine.settings.voiceEngine))
                                .hudText(.meta)
                                .foregroundStyle(live ? HUD.onSignal.opacity(0.75) : HUD.fg1)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 14)
                        .frame(minWidth: 120, minHeight: 56, alignment: .leading)
                        .background(Chamfer(cut: 6).fill(live ? HUD.signal : HUD.bg1))
                        .overlay(Chamfer(cut: 6).stroke(live ? HUD.signal : HUD.ruleStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(member.name)\(live ? ", speaking" : ""). Jump to next line")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .animation(.snappy, value: reader.currentSpeaker)
    }
}

/// Everyone in the dialogue: pick a voice and a pace for each, and hear a line.
struct CastSheet: View {
    @Environment(Engine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    let document: Document

    @State private var cast = Cast()
    @State private var appleVoices: [AVSpeechSynthesisVoice] = []

    private var reader: Reader { engine.reader }
    private var usesKokoro: Bool { engine.settings.voiceEngine == .kokoro && KokoroVoice.shared.modelsPresent }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(usesKokoro ? "KOKORO VOICES · ON THIS IPHONE" : "APPLE VOICES · ON THIS IPHONE")
                        .hudText(.label)
                        .foregroundStyle(HUD.fg1)
                        .listRowBackground(HUD.bg1)
                    ForEach(cast.members) { member in
                        memberRow(member)
                            .listRowBackground(HUD.bg1)
                    }
                } footer: {
                    Text("Narrator reads stage directions and anything outside the dialogue, in your usual voice. Tap HEAR to jump to a character's next line.")
                        .hudText(.meta)
                        .foregroundStyle(HUD.fg1)
                }
            }
            .scrollContentBackground(.hidden)
            .background(HUD.bg1)
            .navigationTitle("Cast · \(max(0, cast.members.count - 1))")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Recast", systemImage: "arrow.triangle.2.circlepath") {
                        document.cast = nil
                        engine.assignCastIfNeeded(document)
                        cast = document.cast ?? Cast()
                        engine.updateCast(cast, for: document)
                    }
                }
            }
        }
        .presentationBackground(HUD.bg1)
        .onAppear {
            cast = document.cast ?? Cast()
            // The ten natural voices, plus your Personal Voice first when you have one:
            // a character can speak in your voice.
            let personal = AVSpeechSynthesisVoice.speechVoices().filter { $0.voiceTraits.contains(.isPersonalVoice) }
            appleVoices = personal + Reader.castableVoices()
        }
    }

    private func memberRow(_ member: CastMember) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(member.name.uppercased())
                    .hudText(.label)
                    .foregroundStyle(member.id == reader.currentSpeaker ? HUD.signalInk : HUD.fg0)
                voiceMenu(member)
            }
            Spacer()
            paceMenu(member)
            if !member.isNarrator {
                Button("Hear") {
                    reader.jumpToNextTurn(of: member.id)
                    if !reader.isSpeaking || reader.isPaused { engine.playReading(document) }
                }
                .buttonStyle(HUDButtonStyle(size: 44))
                .accessibilityLabel("Hear \(member.name)")
            }
        }
        .padding(.vertical, 6)
    }

    private func voiceMenu(_ member: CastMember) -> some View {
        Menu {
            if usesKokoro {
                ForEach(KokoroVoice.englishVoices, id: \.id) { voice in
                    Button("\(voice.name) · \(voice.detail)") {
                        var m = member
                        m.kokoroVoiceID = voice.id
                        save(m)
                        Task { await KokoroVoice.shared.preload(voice: voice.id) }
                    }
                }
            } else {
                ForEach(appleVoices, id: \.identifier) { voice in
                    Button(voice.voiceTraits.contains(.isPersonalVoice) ? "Your Voice · \(Self.quality(voice))" : "\(voice.name) · \(Self.quality(voice))") {
                        var m = member
                        m.voiceIdentifier = voice.identifier
                        save(m)
                    }
                }
            }
        } label: {
            Text("VOICE · \(Self.voiceName(for: member, engine: engine.settings.voiceEngine).uppercased()) ▾")
                .hudText(.meta)
                .foregroundStyle(HUD.fg1)
        }
    }

    private func paceMenu(_ member: CastMember) -> some View {
        Menu {
            ForEach([0.85, 0.92, 1.0, 1.08, 1.15], id: \.self) { pace in
                Button(String(format: "%.2f× pace", pace)) {
                    var m = member
                    m.pace = pace
                    save(m)
                }
            }
            if !usesKokoro {
                Divider()
                ForEach([0.8, 0.9, 1.0, 1.1, 1.2], id: \.self) { pitch in
                    Button(String(format: "%.1f pitch", pitch)) {
                        var m = member
                        m.pitch = pitch
                        save(m)
                    }
                }
            }
        } label: {
            Text(String(format: "%.2f×", member.pace))
                .hudText(.meta)
                .foregroundStyle(HUD.fg0)
                .frame(minWidth: 44, minHeight: 44)
                .overlay(Rectangle().strokeBorder(HUD.rule, lineWidth: 1))
        }
    }

    private func save(_ member: CastMember) {
        cast.update(member)
        engine.updateCast(cast, for: document)
    }

    static func voiceName(for member: CastMember, engine: Settings.VoiceEngineChoice) -> String {
        if engine == .kokoro, let id = member.kokoroVoiceID {
            return KokoroVoice.englishVoices.first { $0.id == id }?.name ?? id
        }
        if let id = member.voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: id) {
            return voice.voiceTraits.contains(.isPersonalVoice) ? "Your Voice" : voice.name
        }
        return member.isNarrator ? "Your voice" : "Default"
    }

    private static func quality(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Compact"
        }
    }
}
