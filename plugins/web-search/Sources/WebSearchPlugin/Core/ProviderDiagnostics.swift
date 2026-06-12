import Foundation

enum ProviderDiagnosticState: String, Codable, Sendable, CaseIterable, Equatable {
    case ok
    case empty
    case blocked
    case botPolicyBlocked = "bot_policy_blocked"
    case rateLimited = "rate_limited"
    case captcha
    case loginWall = "login_wall"
    case javascriptRequired = "javascript_required"
    case unsupportedContent = "unsupported_content"
    case providerTermsBlocked = "provider_terms_blocked"
    case parseFailed = "parse_failed"
    case timeout
    case disabled
}

struct ProviderDiagnostic: Codable, Sendable, Equatable {
    var providerID: String
    var state: ProviderDiagnosticState
    var message: String
    var retrievedAt: Date
    var sourceURL: String?

    init(
        providerID: String,
        state: ProviderDiagnosticState,
        message: String,
        retrievedAt: Date = Date(),
        sourceURL: String? = nil
    ) {
        self.providerID = providerID
        self.state = state
        self.message = message
        self.retrievedAt = retrievedAt
        self.sourceURL = sourceURL
    }
}
