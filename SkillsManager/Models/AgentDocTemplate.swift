import Foundation

struct AgentDocTemplate: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var fileName: String
    var content: String
}
