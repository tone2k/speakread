import AppIntents

/// "Hey Siri, start Verso" starts a recording from any pose.
struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start recording"
    static var description = IntentDescription("Starts a new recording in Verso.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Engine.shared.startRecording()
        return .result()
    }
}

struct VersoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Start \(.applicationName)",
                "Start recording in \(.applicationName)",
                "Record with \(.applicationName)"
            ],
            shortTitle: "Start recording",
            systemImageName: "record.circle"
        )
    }
}
