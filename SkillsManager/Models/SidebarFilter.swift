import Foundation

enum SidebarFilter: Hashable, Sendable {
    case controlCenter
    case discover
    case all
    case installed
    case starred
    case trial
    case conflicts
    case project
    case agentDocs
    case agent(String)
    case source(String)
    case collection(UUID, name: String)

    var title: String {
        switch self {
        case .controlCenter:        String(localized: "Control Center")
        case .discover:             String(localized: "Discover")
        case .all:                  String(localized: "All Skills")
        case .installed:            String(localized: "Installed")
        case .starred:              String(localized: "Starred")
        case .trial:                String(localized: "Trial")
        case .conflicts:            String(localized: "Conflicts")
        case .project:              String(localized: "Project")
        case .agentDocs:            String(localized: "Agent Docs")
        case .agent(let name):      name
        case .source(let name):     name
        case .collection(_, let name): name
        }
    }

    var icon: String {
        switch self {
        case .controlCenter: "switch.2"
        case .discover:      "safari"
        case .all:           "square.grid.2x2"
        case .installed:     "checkmark.circle"
        case .starred:       "star.fill"
        case .trial:         "flask"
        case .conflicts:     "exclamationmark.triangle"
        case .project:       "folder"
        case .agentDocs:     "doc.text"
        case .agent:         "cpu"
        case .source:        "shippingbox"
        case .collection:    "folder.fill"
        }
    }
}
