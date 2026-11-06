import SwiftUI
import SwiftData

@main
struct VersoApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Document.self, Note.self)
        } catch {
            fatalError("Verso could not open its library: \(error)")
        }
        Engine.shared.attach(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(Engine.shared)
                .tint(HUD.signal)
                .onOpenURL { url in
                    Task { await Engine.shared.importFile(at: url) }
                }
        }
        .modelContainer(container)
    }
}
