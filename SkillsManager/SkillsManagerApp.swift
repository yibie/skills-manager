import SwiftUI
import SwiftData

@main
struct SkillsManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        if !Self.usesUIStateMatrixFixture {
            AppSettings.migrateApiKeysToKeychainIfNeeded()
        }
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SkillRecord.self,
            CollectionRecord.self,
        ])
        let config = ModelConfiguration(
            "SkillsManager",
            schema: schema,
            isStoredInMemoryOnly: Self.usesUIStateMatrixFixture
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
        .commands {
            SkillCommands()
        }

        Settings {
            SettingsView()
                .disabled(Self.usesUIStateMatrixFixture)
        }
    }

    private static var usesUIStateMatrixFixture: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-state-matrix")
        #else
        false
        #endif
    }
}
