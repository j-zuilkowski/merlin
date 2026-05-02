import Foundation

actor ThreadAutomationEngine {
    private var onFire: (@Sendable (UUID, String) -> Void)?
    private var loopTask: Task<Void, Never>?
    private var pending: [(ThreadAutomation, Date)] = []

    func setOnFire(_ handler: @escaping @Sendable (UUID, String) -> Void) {
        onFire = handler
    }

    func start(store: ThreadAutomationStore) async {
        stop()
        let automations = await store.all()
        let now = Date()
        pending = automations.compactMap { automation in
            guard automation.enabled,
                  let next = nextFire(for: automation.cronExpression, after: now) else {
                return nil
            }
            return (automation, next)
        }
        scheduleLoop()
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    func scheduleImmediate(automation: ThreadAutomation, fireAfter: TimeInterval) {
        pending.append((automation, Date().addingTimeInterval(fireAfter)))
        scheduleLoop()
    }

    nonisolated func nextFire(for expression: String, after date: Date) -> Date? {
        let fields = expression.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count == 5 else {
            return nil
        }

        let calendar = Calendar(identifier: .gregorian)
        let limit = date.addingTimeInterval(366 * 24 * 60 * 60)
        var search = calendar.date(byAdding: .minute, value: 1, to: date) ?? date.addingTimeInterval(60)

        while search <= limit {
            let components = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: search)
            guard Self.matches(fields[0], components.minute),
                  Self.matches(fields[1], components.hour),
                  Self.matches(fields[2], components.day),
                  Self.matches(fields[3], components.month),
                  Self.matchesWeekday(fields[4], components.weekday) else {
                search = calendar.date(byAdding: .minute, value: 1, to: search) ?? search.addingTimeInterval(60)
                continue
            }
            return search
        }

        return nil
    }

    private func scheduleLoop() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            while Task.isCancelled == false {
                guard let self else {
                    return
                }
                await self.checkAndFire()
                do {
                    try await Task.sleep(for: .milliseconds(1000))
                } catch {
                    return
                }
            }
        }
    }

    private func checkAndFire() {
        let now = Date()
        var remaining: [(ThreadAutomation, Date)] = []

        for (automation, fireDate) in pending {
            if now >= fireDate {
                onFire?(automation.sessionID, automation.prompt)
                if let next = nextFire(for: automation.cronExpression, after: now) {
                    remaining.append((automation, next))
                }
            } else {
                remaining.append((automation, fireDate))
            }
        }

        pending = remaining
    }

    private static func matches(_ field: Substring, _ value: Int?) -> Bool {
        guard let value else {
            return false
        }
        if field == "*" {
            return true
        }
        return Int(field) == value
    }

    private static func matchesWeekday(_ field: Substring, _ value: Int?) -> Bool {
        guard let value else {
            return false
        }
        let cronWeekday = (value + 6) % 7
        if field == "*" {
            return true
        }
        return Int(field) == cronWeekday
    }
}
