import Foundation

struct WorkingSetBudget: Sendable, Equatable, Codable {
    let systemPromptCap: Int
    let ragInjectionCap: Int
    let recentTurnsCap: Int
    let toolBurstCap: Int

    var total: Int {
        systemPromptCap + ragInjectionCap + recentTurnsCap + toolBurstCap
    }

    static let componentFloor = 256

    static func derive(from budget: ProviderBudget) -> WorkingSetBudget {
        let usable = max(0, budget.usableInputTokens)
        let floorsTotal = componentFloor * 4
        if usable < floorsTotal {
            TelemetryEmitter.shared.emit("engine.workingset.budget_too_small", data: [
                "usable": usable,
                "floors_total": floorsTotal
            ])
            return WorkingSetBudget(
                systemPromptCap: componentFloor,
                ragInjectionCap: componentFloor,
                recentTurnsCap: componentFloor,
                toolBurstCap: componentFloor
            )
        }

        let weights: [Double] = [0.10, 0.25, 0.50, 0.15]
        let raw = weights.map { Double(usable) * $0 }
        var caps = raw.map { max(componentFloor, Int(floor($0))) }

        let fractionalOrder = raw.enumerated()
            .sorted { lhs, rhs in
                let lhsFraction = lhs.element - floor(lhs.element)
                let rhsFraction = rhs.element - floor(rhs.element)
                if lhsFraction == rhsFraction { return lhs.offset < rhs.offset }
                return lhsFraction > rhsFraction
            }
            .map(\.offset)

        var difference = usable - caps.reduce(0, +)
        if difference > 0 {
            var index = 0
            while difference > 0 && !fractionalOrder.isEmpty {
                let slot = fractionalOrder[index % fractionalOrder.count]
                caps[slot] += 1
                difference -= 1
                index += 1
            }
        } else if difference < 0 {
            var overflow = -difference
            let reductionOrder = caps.enumerated()
                .sorted { lhs, rhs in
                    if lhs.element == rhs.element { return lhs.offset < rhs.offset }
                    return lhs.element > rhs.element
                }
                .map(\.offset)

            while overflow > 0 {
                var progressed = false
                for slot in reductionOrder {
                    let available = caps[slot] - componentFloor
                    guard available > 0 else { continue }
                    let delta = min(available, overflow)
                    caps[slot] -= delta
                    overflow -= delta
                    progressed = true
                    if overflow == 0 { break }
                }
                if !progressed { break }
            }
        }

        return WorkingSetBudget(
            systemPromptCap: caps[0],
            ragInjectionCap: caps[1],
            recentTurnsCap: caps[2],
            toolBurstCap: caps[3]
        )
    }
}
