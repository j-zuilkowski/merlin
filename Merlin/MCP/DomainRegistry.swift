import Foundation

/// Runtime registry of domain plugins. One active domain at a time.
/// Multi-domain sessions are deferred.
actor DomainRegistry {

    static let shared = DomainRegistry()

    private var plugins: [String: any DomainPlugin] = [:]
    private var activeDomainIDs: [String] = SoftwareDomain.defaultActiveDomainIDs

    init() {
        // SoftwareDomain is always registered and cannot be removed.
        let software = SoftwareDomain()
        plugins[software.id] = software
    }

    func register(_ plugin: any DomainPlugin) {
        plugins[plugin.id] = plugin
    }

    func unregister(id: String) {
        guard id != SoftwareDomain.defaultID else { return }
        plugins.removeValue(forKey: id)
        activeDomainIDs = normalizeActiveDomainIDs(activeDomainIDs.filter { $0 != id })
    }

    func setActiveDomain(id: String) {
        setActiveDomains(ids: [id])
    }

    func activeDomain() -> any DomainPlugin {
        let domains = activeDomains()
        return domains.first(where: { $0.id != SoftwareDomain.defaultID }) ?? domains.first ?? SoftwareDomain()
    }

    func activeDomains() -> [any DomainPlugin] {
        activeDomainIDs.compactMap { plugins[$0] }
    }

    func activeDomains(ids: [String]) -> [any DomainPlugin] {
        normalizeActiveDomainIDs(ids).compactMap { plugins[$0] }
    }

    func normalizedActiveDomainIDs(ids: [String]) -> [String] {
        normalizeActiveDomainIDs(ids)
    }

    func activeDomain(ids: [String]) -> any DomainPlugin {
        let domains = activeDomains(ids: ids)
        return domains.first(where: { $0.id != SoftwareDomain.defaultID }) ?? domains.first ?? SoftwareDomain()
    }

    func taskTypes(ids: [String]) -> [DomainTaskType] {
        activeDomains(ids: ids).flatMap { $0.taskTypes }
    }

    func setActiveDomains(ids: [String]) {
        activeDomainIDs = normalizeActiveDomainIDs(ids)
    }

    /// Returns task types for all active domains, preserving the registered order.
    /// Software remains part of the merged set so the base `code_generation` task stays visible.
    func taskTypes() -> [DomainTaskType] {
        activeDomains().flatMap { $0.taskTypes }
    }

    func plugin(for id: String) -> (any DomainPlugin)? {
        plugins[id]
    }

    private func normalizeActiveDomainIDs(_ ids: [String]) -> [String] {
        var normalized: [String] = SoftwareDomain.defaultActiveDomainIDs
        for id in ids {
            guard id != SoftwareDomain.defaultID, plugins[id] != nil else { continue }
            if !normalized.contains(id) {
                normalized.append(id)
            }
        }
        return normalized.isEmpty ? SoftwareDomain.defaultActiveDomainIDs : normalized
    }
}
