import Foundation

enum SidebarFilter: Hashable, Sendable {
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

    var title: String {
        switch self {
        case .discover:         "Discover"
        case .all:              "All Skills"
        case .installed:        "Installed"
        case .starred:          "Starred"
        case .trial:            "Trial"
        case .conflicts:        "Conflicts"
        case .project:          "Project"
        case .agentDocs:        "Agent Docs"
        case .agent(let name):  name
        case .source(let name): name
        }
    }

    var icon: String {
        switch self {
        case .discover:  "safari"
        case .all:       "square.grid.2x2"
        case .installed: "checkmark.circle"
        case .starred:   "star.fill"
        case .trial:     "flask"
        case .conflicts: "exclamationmark.triangle"
        case .project:   "folder"
        case .agentDocs: "doc.text"
        case .agent:     "cpu"
        case .source:    "shippingbox"
        }
    }
}
