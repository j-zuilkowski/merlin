import Foundation

/// Runtime registry of domain plugins. One active domain at a time.
/// Multi-domain sessions are deferred.
actor DomainRegistry {

    static let shared = DomainRegistry()

    private var plugins: [String: any DomainPlugin] = [:]
    private var activeDomainIDs: [String] = ["software"]

    init() {
        // SoftwareDomain is always registered and cannot be removed.
        let software = SoftwareDomain()
        plugins[software.id] = software
    }

    func register(_ plugin: any DomainPlugin) {
        plugins[plugin.id] = plugin
    }

    func unregister(id: String) {
        guard id != "software" else { return }
        plugins.removeValue(forKey: id)
        activeDomainIDs = normalizeActiveDomainIDs(activeDomainIDs.filter { $0 != id })
    }

    func setActiveDomain(id: String) {
        setActiveDomains(ids: [id])
    }

    func activeDomain() -> any DomainPlugin {
        let domains = activeDomains()
        return domains.first(where: { $0.id != "software" }) ?? domains.first ?? SoftwareDomain()
    }

    func activeDomains() -> [any DomainPlugin] {
        activeDomainIDs.compactMap { plugins[$0] }
    }

    func activeDomains(ids: [String]) -> [any DomainPlugin] {
        normalizeActiveDomainIDs(ids).compactMap { plugins[$0] }
    }

    func activeDomain(ids: [String]) -> any DomainPlugin {
        let domains = activeDomains(ids: ids)
        return domains.first(where: { $0.id != "software" }) ?? domains.first ?? SoftwareDomain()
    }

    func taskTypes(ids: [String]) -> [DomainTaskType] {
        activeDomains(ids: ids).flatMap { $0.taskTypes }
    }

    func setActiveDomains(ids: [String]) {
        activeDomainIDs = normalizeActiveDomainIDs(ids)
    }

    /// Returns task types for every active domain in order.
    func taskTypes() -> [DomainTaskType] {
        activeDomains().flatMap { $0.taskTypes }
    }

    func plugin(for id: String) -> (any DomainPlugin)? {
        plugins[id]
    }

    private func normalizeActiveDomainIDs(_ ids: [String]) -> [String] {
        var normalized: [String] = ["software"]
        for id in ids {
            guard id != "software", plugins[id] != nil else { continue }
            if !normalized.contains(id) {
                normalized.append(id)
            }
        }
        return normalized.isEmpty ? ["software"] : normalized
    }
}
