import Foundation

enum DiscoverDirectoryCategory: String, CaseIterable, Identifiable, Sendable {
    case allTime
    case trending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allTime: "All Time"
        case .trending: "Trending"
        }
    }

    var pathComponent: String {
        switch self {
        case .allTime: ""
        case .trending: "trending"
        }
    }

    var url: URL {
        if pathComponent.isEmpty {
            return URL(string: "https://skills.sh/")!
        }
        return URL(string: "https://skills.sh/\(pathComponent)")!
    }
}
