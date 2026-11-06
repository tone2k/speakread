import SwiftUI

/// A meeting's digest: summary, decisions, actions, open questions, topics,
/// people. Made on the phone. Regenerate or share from the top strip.
struct DigestView: View {
    let document: Document

    private var digester: MeetingDigester { MeetingDigester.shared }

    var body: some View {
        let busy = digester.inFlight.contains(document.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    if busy { BlinkDot(size: 8) }
                    Text(busy ? "DIGESTING · ON-DEVICE" : (document.digest == nil ? "NO DIGEST" : "DIGEST · \(stamp(document.digest?.generatedAt))"))
                        .hudText(.label)
                        .foregroundStyle(busy ? HUD.signalInk : HUD.fg1)
                    Spacer()
                    if let digest = document.digest {
                        ShareLink(item: digest.markdown, subject: Text(digest.title)) {
                            Text("SHARE")
                        }
                        .buttonStyle(HUDButtonStyle(size: 32))
                    }
                    Button(document.digest == nil ? "DIGEST" : "REDO") {
                        digester.digest(document)
                    }
                    .buttonStyle(HUDButtonStyle(size: 32, primary: document.digest == nil))
                    .disabled(busy || !MeetingDigester.isAvailable)
                }

                if !MeetingDigester.isAvailable {
                    Text("Apple's on-device model is not available on this iPhone, so Verso cannot digest here.")
                        .hudText(.body)
                        .foregroundStyle(HUD.fg1)
                } else if let error = digester.lastError, document.digest == nil, !busy {
                    Text("FAULT · \(error)")
                        .hudText(.label)
                        .foregroundStyle(HUD.caution)
                }

                if let digest = document.digest {
                    content(digest)
                } else if !busy {
                    Text("A digest is the meeting in the parts a person needs: what was decided, who does what, what stayed open. Verso makes it on the phone. Nothing leaves.")
                        .hudText(.body)
                        .foregroundStyle(HUD.fg1)
                }
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func content(_ digest: MeetingDigest) -> some View {
        Text(digest.title)
            .hudText(.title2)
            .foregroundStyle(HUD.fg0)
        Text(digest.summary)
            .hudText(.body)
            .foregroundStyle(HUD.fg0)

        if !digest.decisions.isEmpty {
            section("DECISIONS · \(digest.decisions.count)") {
                ForEach(Array(digest.decisions.enumerated()), id: \.offset) { i, item in
                    row(index: i, text: item)
                }
            }
        }
        if !digest.actions.isEmpty {
            section("ACTIONS · \(digest.actions.count)") {
                ForEach(digest.actions) { action in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.task)
                            .hudText(.body)
                            .foregroundStyle(HUD.fg0)
                        Text(actionMeta(action))
                            .hudText(.label)
                            .foregroundStyle(HUD.signalInk)
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Rectangle().fill(HUD.rule).frame(height: 1) }
                }
            }
        }
        if !digest.questions.isEmpty {
            section("OPEN · \(digest.questions.count)") {
                ForEach(Array(digest.questions.enumerated()), id: \.offset) { i, item in
                    row(index: i, text: item)
                }
            }
        }
        if !digest.topics.isEmpty {
            section("TOPICS") {
                Text(digest.topics.joined(separator: " · ").uppercased())
                    .hudText(.meta)
                    .foregroundStyle(HUD.fg1)
                    .padding(.vertical, 6)
            }
        }
        if !digest.participants.isEmpty {
            section("PEOPLE") {
                Text(digest.participants.joined(separator: " · "))
                    .hudText(.meta)
                    .foregroundStyle(HUD.fg1)
                    .padding(.vertical, 6)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(title: title)
            content()
        }
    }

    private func row(index: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(String(format: "%02d", index + 1))
                .hudText(.meta)
                .foregroundStyle(HUD.signalInk)
            Text(text)
                .hudText(.body)
                .foregroundStyle(HUD.fg0)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(HUD.rule).frame(height: 1) }
    }

    private func actionMeta(_ action: MeetingDigest.Action) -> String {
        var parts: [String] = []
        let owner = action.owner.trimmingCharacters(in: .whitespaces)
        if !owner.isEmpty, owner.lowercased() != "unassigned" { parts.append(owner.uppercased()) }
        let due = action.due.trimmingCharacters(in: .whitespaces)
        if !due.isEmpty, due.lowercased() != "none" { parts.append("DUE \(due.uppercased())") }
        return parts.isEmpty ? "UNASSIGNED" : parts.joined(separator: " · ")
    }

    private func stamp(_ date: Date?) -> String {
        guard let date else { return "" }
        let f = DateFormatter()
        f.dateFormat = "dd MMM HH:mm"
        return f.string(from: date).uppercased()
    }
}
