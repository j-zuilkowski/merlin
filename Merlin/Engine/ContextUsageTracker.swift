import Foundation

@MainActor
final class ContextUsageTracker: ObservableObject {
    let contextWindowSize: Int
    @Published private(set) var usedTokens: Int = 0

    init(contextWindowSize: Int) {
        self.contextWindowSize = contextWindowSize
    }

    func update(usedTokens: Int) {
        self.usedTokens = usedTokens
    }

    var percentUsed: Double {
        guard contextWindowSize > 0 else {
            return 0
        }
        return Double(usedTokens) / Double(contextWindowSize)
    }

    var statusString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let used = formatter.string(from: NSNumber(value: usedTokens)) ?? "\(usedTokens)"
        let total = formatter.string(from: NSNumber(value: contextWindowSize)) ?? "\(contextWindowSize)"
        let percent = Int(percentUsed * 100)
        return "Context: \(used) / \(total) tokens (\(percent)%)"
    }
}
