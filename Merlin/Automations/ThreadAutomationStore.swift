import Foundation

actor ThreadAutomationStore {
    private var automations: [UUID: ThreadAutomation] = [:]
    private var order: [UUID] = []

    func add(_ automation: ThreadAutomation) throws {
        guard automations[automation.id] == nil else {
            return
        }
        automations[automation.id] = automation
        order.append(automation.id)
    }

    func remove(id: UUID) throws {
        automations.removeValue(forKey: id)
        order.removeAll { $0 == id }
    }

    func all() async -> [ThreadAutomation] {
        order.compactMap { automations[$0] }
    }

    func update(_ automation: ThreadAutomation) {
        guard automations[automation.id] != nil else {
            return
        }
        automations[automation.id] = automation
    }
}
