import AppIntents
import Foundation

protocol MerlinAppIntentActionHandling {
    func startSession() async throws
    func sendPrompt(_ prompt: String) async throws
}

final class MerlinAppIntentActionRouter: @unchecked Sendable, MerlinAppIntentActionHandling {
    static let shared = MerlinAppIntentActionRouter()

    var startSessionAction: (() -> Void)?
    var sendPromptAction: ((String) -> Void)?

    func startSession() async throws {
        startSessionAction?()
    }

    func sendPrompt(_ prompt: String) async throws {
        sendPromptAction?(prompt)
    }
}

enum MerlinAppIntentsSupport {
    nonisolated(unsafe) static var actionHandler: any MerlinAppIntentActionHandling = MerlinAppIntentActionRouter.shared

    static let userFacingIntentTypes: [any AppIntent.Type] = [
        StartMerlinSessionIntent.self,
        SendMerlinPromptIntent.self,
    ]

    static func install(appState: AppState) {
        MerlinAppIntentActionRouter.shared.startSessionAction = { [weak appState] in
            Task { @MainActor in
                appState?.startSessionFromAppIntent()
            }
        }
        MerlinAppIntentActionRouter.shared.sendPromptAction = { [weak appState] prompt in
            guard let appState else { return }
            Task { @MainActor in
                await appState.sendPromptFromAppIntent(prompt)
            }
        }
        actionHandler = MerlinAppIntentActionRouter.shared
    }
}

struct MerlinMetadataIntent: AppIntent {
    static let title: LocalizedStringResource = "Merlin Metadata"

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct StartMerlinSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Merlin Session"
    static let description = IntentDescription("Starts a new Merlin session.")

    func perform() async throws -> some IntentResult {
        try await MerlinAppIntentsSupport.actionHandler.startSession()
        return .result()
    }
}

struct SendMerlinPromptIntent: AppIntent {
    static let title: LocalizedStringResource = "Send Merlin Prompt"
    static let description = IntentDescription("Sends a prompt to the current Merlin session.")

    var prompt: String = ""

    func perform() async throws -> some IntentResult {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw SendMerlinPromptIntentError.emptyPrompt
        }

        try await MerlinAppIntentsSupport.actionHandler.sendPrompt(prompt)
        return .result()
    }
}

enum SendMerlinPromptIntentError: LocalizedError {
    case emptyPrompt

    var errorDescription: String? {
        switch self {
        case .emptyPrompt:
            return "Prompt cannot be empty."
        }
    }
}
