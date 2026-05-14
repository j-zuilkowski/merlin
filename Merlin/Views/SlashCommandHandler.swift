import Foundation

enum SlashCommandOutcome: Sendable, Equatable {
    case consumed
    case notHandled
}

struct SlashCommandHandler {
    private let onCompact: () -> Void
    private let onCalibrate: () -> Void

    init(
        onCompact: @escaping () -> Void,
        onCalibrate: @escaping () -> Void
    ) {
        self.onCompact = onCompact
        self.onCalibrate = onCalibrate
    }

    func handle(_ message: String) -> SlashCommandOutcome {
        guard message.hasPrefix("/") else {
            return .notHandled
        }

        let parts = message.dropFirst().split(whereSeparator: \.isWhitespace)
        let command = parts.first.map(String.init)?.lowercased() ?? ""

        switch command {
        case "compact":
            onCompact()
            return .consumed

        case "calibrate":
            onCalibrate()
            return .consumed

        default:
            return .notHandled
        }
    }
}
