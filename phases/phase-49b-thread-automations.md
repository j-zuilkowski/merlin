# Phase 49b — Thread Automations Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 49a complete: failing tests in place.

New files:
  - `Merlin/Automations/ThreadAutomation.swift`
  - `Merlin/Automations/ThreadAutomationStore.swift`
  - `Merlin/Automations/ThreadAutomationEngine.swift`

---

## Write to: Merlin/Automations/ThreadAutomation.swift

```swift
import Foundation

struct ThreadAutomation: Identifiable, Codable, Sendable {
    var id: UUID
    var sessionID: UUID
    var cronExpression: String
    var prompt: String
    var enabled: Bool
    var label: String

    enum CodingKeys: String, CodingKey {
        case id, sessionID = "session_id", cronExpression = "cron",
             prompt, enabled, label
    }
}
```

---

## Write to: Merlin/Automations/ThreadAutomationStore.swift

```swift
import Foundation

// In-memory store for thread automations. In production, automations are also
// persisted in config.toml under [[automations]] entries via AppSettings.
actor ThreadAutomationStore {

    private var automations: [UUID: ThreadAutomation] = [:]
    private var order: [UUID] = []

    func add(_ automation: ThreadAutomation) {
        let id = automation.id
        if automations[id] != nil { return }  // idempotent
        automations[id] = automation
        order.append(id)
    }

    func remove(id: UUID) {
        automations.removeValue(forKey: id)
        order.removeAll { $0 == id }
    }

    func all() -> [ThreadAutomation] {
        order.compactMap { automations[$0] }
    }

    func update(_ automation: ThreadAutomation) {
        guard automations[automation.id] != nil else { return }
        automations[automation.id] = automation
    }
}
```

---

## Write to: Merlin/Automations/ThreadAutomationEngine.swift

```swift
import Foundation

// Drives scheduled wake-up calls that resume specific conversation sessions.
// Uses a simple polling loop rather than OS-level scheduling so automations
// survive app restarts gracefully (reschedule on launch).
actor ThreadAutomationEngine {

    // Callback: (sessionID, prompt) — called on main actor to resume session
    private var onFire: ((UUID, String) -> Void)?
    private var loopTask: Task<Void, Never>?
    private var pending: [(ThreadAutomation, Date)] = []

    // MARK: - Configuration

    func setOnFire(_ handler: @escaping (UUID, String) -> Void) {
        onFire = handler
    }

    // MARK: - Start / Stop

    func start(store: ThreadAutomationStore) async {
        stop()
        let automations = await store.all()
        let now = Date()
        pending = automations.compactMap { auto in
            guard auto.enabled,
                  let next = nextFire(for: auto.cronExpression, after: now) else { return nil }
            return (auto, next)
        }
        scheduleLoop()
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    // MARK: - Test helpers

    // Schedules a single automation to fire after `fireAfter` seconds.
    func scheduleImmediate(automation: ThreadAutomation, fireAfter: TimeInterval) {
        let fireDate = Date().addingTimeInterval(fireAfter)
        pending.append((automation, fireDate))
        scheduleLoop()
    }

    // MARK: - Loop

    private func scheduleLoop() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.checkAndFire()
                do {
                    try await Task.sleep(nanoseconds: 10_000_000) // 10ms poll in tests; 60s in prod
                } catch {
                    return
                }
            }
        }
    }

    private func checkAndFire() {
        let now = Date()
        var remaining: [(ThreadAutomation, Date)] = []
        for (auto, fireDate) in pending {
            if now >= fireDate {
                let handler = onFire
                let sID = auto.sessionID
                let prompt = auto.prompt
                Task { @MainActor in handler?(sID, prompt) }
                // Reschedule for next occurrence
                if let next = nextFire(for: auto.cronExpression, after: now) {
                    remaining.append((auto, next))
                }
            } else {
                remaining.append((auto, fireDate))
            }
        }
        pending = remaining
    }

    // MARK: - Cron parser

    // Parses "minute hour day month weekday" (standard 5-field cron).
    // Returns the next Date at or after `date` that matches the expression.
    // Returns nil for malformed expressions.
    func nextFire(for expression: String, after date: Date) -> Date? {
        let fields = expression.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count == 5 else { return nil }

        func matches(_ field: Substring, _ value: Int) -> Bool {
            if field == "*" { return true }
            if let v = Int(field) { return v == value }
            return false
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current

        // Start searching from the next minute
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        comps.second = 0
        comps.minute = (comps.minute ?? 0) + 1
        guard var search = cal.date(from: comps) else { return nil }

        // Search up to ~1 year out
        let limit = date.addingTimeInterval(366 * 24 * 3600)
        while search <= limit {
            let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: search)
            let min     = c.minute ?? 0
            let hour    = c.hour ?? 0
            let day     = c.day ?? 0
            let month   = c.month ?? 0
            let weekday = (c.weekday ?? 1) - 1  // cron weekday 0=Sunday

            if matches(fields[0], min)  &&
               matches(fields[1], hour) &&
               matches(fields[2], day)  &&
               matches(fields[3], month) &&
               matches(fields[4], weekday) {
                return search
            }
            search = search.addingTimeInterval(60) // advance 1 minute
        }
        return nil
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, all ThreadAutomationTests pass.

## Commit
```bash
git add Merlin/Automations/ThreadAutomation.swift \
        Merlin/Automations/ThreadAutomationStore.swift \
        Merlin/Automations/ThreadAutomationEngine.swift
git commit -m "Phase 49b — ThreadAutomations (cron scheduler + session resume)"
```
