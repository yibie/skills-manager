# Views Review: Agent Docs Manager

## Blocking Fix Applied

- `InstallToAgentView.swift` and `DiscoverInstallToAgentView.swift` duplicated the same agent multi-select/import-folder UI. This was the only blocker for adding a third target picker. Fixed by extracting `AgentMultiSelectList`.

## Findings

- `DiscoverView.swift` is 914 lines and contains multiple independent screens (`DiscoverDetailView`, `DiscoverTryView`). Split later for navigation and reviewability; not blocking Agent Docs.
- `ContentView.swift` keeps growing as the split-view router. Agent Docs adds one more branch, but the existing dumb-view/closure pattern still holds. Consider extracting route-specific builders later.
- `SidebarView.swift` still does installed-agent filesystem detection from computed view state. Agent Docs avoids copying that pattern; leave the existing behavior alone unless sidebar rendering becomes visibly slow.
- `SkillListView.swift` and detail views keep task bridging local to button closures. Consistent with current code; no blocking issue found.

## Health Check

- No `force unwrap`, `try!`, or `as!` found in `Views/`.
- New Agent Docs views keep filesystem writes in `SkillStore`/services, not views.
- New template editing uses `NSWorkspace` only, matching existing app behavior.
