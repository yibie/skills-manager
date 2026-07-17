import SwiftUI

/// Actions exposed by the content view to the app-level "Skill" menu.
struct SkillCommandActions {
    var refresh: () -> Void
    /// nil when no library skill is selected.
    var toggleStar: (() -> Void)?
    var isStarred: Bool
}

struct SkillCommandActionsKey: FocusedValueKey {
    typealias Value = SkillCommandActions
}

extension FocusedValues {
    var skillCommandActions: SkillCommandActions? {
        get { self[SkillCommandActionsKey.self] }
        set { self[SkillCommandActionsKey.self] = newValue }
    }
}

struct SkillCommands: Commands {
    @FocusedValue(\.skillCommandActions) private var actions

    var body: some Commands {
        CommandMenu("Skill") {
            Button("Refresh Skills") { actions?.refresh() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(actions == nil)

            Divider()

            Button(actions?.isStarred == true ? "Unstar" : "Star") { actions?.toggleStar?() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(actions?.toggleStar == nil)
        }
    }
}
