import Foundation

struct BotPolicyDecision: Sendable, Equatable {
    var blocked: Bool
    var diagnostic: ProviderDiagnostic?
}

enum BotPolicy {
    static func evaluate(html: String, settings: WebSearchSettings, providerID: String = "extractor") -> BotPolicyDecision {
        let lower = html.lowercased()
        if lower.contains("captcha") || lower.contains("bot challenge") || lower.contains("cf-challenge") {
            return blocked(providerID: providerID, state: .captcha, message: "Page requires CAPTCHA or challenge handling")
        }
        if lower.contains("sign in") || lower.contains("log in") || lower.contains("login required") || lower.contains("authentication required") {
            return blocked(providerID: providerID, state: .loginWall, message: "Page requires login or authentication")
        }
        if lower.contains("enable javascript") || lower.contains("javascript is required") {
            return blocked(providerID: providerID, state: .javascriptRequired, message: "Page requires JavaScript rendering")
        }
        if lower.contains("terms of service") && (lower.contains("automated") || lower.contains("scraping") || lower.contains("robots")) {
            return blocked(providerID: providerID, state: .providerTermsBlocked, message: "Provider terms block automated extraction")
        }
        guard hasRobotsAdvisory(lower) else {
            return BotPolicyDecision(blocked: false, diagnostic: nil)
        }
        switch settings.botPolicyMode {
        case .respect:
            return blocked(providerID: providerID, state: .botPolicyBlocked, message: "Robots/noindex advisory policy blocked extraction")
        case .ignoreAdvisory:
            return BotPolicyDecision(blocked: false, diagnostic: ProviderDiagnostic(providerID: providerID, state: .ok, message: "Advisory bot policy ignored by user setting"))
        }
    }

    private static func hasRobotsAdvisory(_ lower: String) -> Bool {
        lower.contains("name=\"robots\"")
            && (lower.contains("noarchive")
                || lower.contains("noai")
                || lower.contains("nofollow")
                || lower.contains("noindex")
                || lower.contains("none"))
    }

    private static func blocked(providerID: String, state: ProviderDiagnosticState, message: String) -> BotPolicyDecision {
        BotPolicyDecision(blocked: true, diagnostic: ProviderDiagnostic(providerID: providerID, state: state, message: message))
    }
}
