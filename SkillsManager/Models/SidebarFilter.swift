import Foundation

enum SidebarFilter: Hashable, Sendable {
    case all
    case installed
    case starred
    case trial
    case agent(String)
    case source(String)

    var title: String {
        switch self {
        case .all: "All Skills"
        case .installed: "Installed"
        case .starred: "Starred"
        case .trial: "Trial"
        case .agent(let name): name
        case .source(let name): name
        }
    }

    var icon: String {
        switch self {
        case .all: "square.grid.2x2"
        case .installed: "checkmark.circle"
        case .starred: "star.fill"
        case .trial: "flask"  // or "testtube.2" on newer macOS
        case .agent: "cpu"
        case .source: "shippingbox"
        }
    }
}
