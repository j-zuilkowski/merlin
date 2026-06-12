import Foundation

struct SearchRequest: Codable, Sendable, Equatable {
    var query: String
    var locale: String?
    var count: Int?
    var freshnessHint: String?
    var allowedDomains: [String]
    var blockedDomains: [String]
    var providerOptions: [String: String]
    var settings: WebSearchSettings?

    init(
        query: String,
        locale: String? = nil,
        count: Int? = nil,
        freshnessHint: String? = nil,
        allowedDomains: [String] = [],
        blockedDomains: [String] = [],
        providerOptions: [String: String] = [:],
        settings: WebSearchSettings? = nil
    ) {
        self.query = query
        self.locale = locale
        self.count = count
        self.freshnessHint = freshnessHint
        self.allowedDomains = allowedDomains
        self.blockedDomains = blockedDomains
        self.providerOptions = providerOptions
        self.settings = settings
    }
}
