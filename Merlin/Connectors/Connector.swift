import Foundation

protocol Connector: Sendable {
    var token: String { get }
    var isConfigured: Bool { get }
    init(token: String)
}

extension Connector {
    var isConfigured: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
