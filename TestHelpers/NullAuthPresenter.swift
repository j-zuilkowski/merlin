import Foundation
@testable import Merlin

final class NullAuthPresenter: AuthPresenter {
    func requestDecision(tool: String, argument: String, suggestedPattern: String) async -> AuthDecision { .deny }
}

final class CapturingAuthPresenter: AuthPresenter {
    let response: AuthDecision
    var wasPrompted = false

    init(response: AuthDecision) { self.response = response }

    func requestDecision(tool: String, argument: String, suggestedPattern: String) async -> AuthDecision {
        wasPrompted = true
        return response
    }
}
