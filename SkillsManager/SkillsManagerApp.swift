import SwiftUI
import SwiftData

@main
struct SkillsManagerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SkillRecord.self,
        ])
        let config = ModelConfiguration(
            "SkillsManager",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)

        Settings {
            SettingsView()
        }
    }
}
