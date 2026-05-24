import Foundation

/// Runtime registry of domain plugins.
actor DomainRegistry {

    static let shared = DomainRegistry()

    private var plugins: [String: any DomainPlugin] = [:]
    private var activeDomainIDs: [String] = SoftwareDomain.defaultActiveDomainIDs

    init() {
        // Built-in domains are always registered and cannot be removed.
        let software = SoftwareDomain()
        plugins[software.id] = software
        let electronics = ElectronicsDomain()
        plugins[electronics.id] = electronics
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

    /// Returns plugins relevant to the active product domains, including
    /// non-selectable external adapters whose canonical domain matches.
    func scopedDomains(ids: [String]) -> [any DomainPlugin] {
        let normalizedIDs = normalizeActiveDomainIDs(ids)
        let allowed = Set(normalizedIDs)
        return plugins.values
            .filter { plugin in
                allowed.contains(plugin.id) || allowed.contains(plugin.canonicalDomainID)
            }
            .sorted { lhs, rhs in
                let leftIndex = normalizedIDs.firstIndex(of: lhs.canonicalDomainID) ?? Int.max
                let rightIndex = normalizedIDs.firstIndex(of: rhs.canonicalDomainID) ?? Int.max
                if leftIndex != rightIndex { return leftIndex < rightIndex }
                if lhs.isUserSelectable != rhs.isUserSelectable { return lhs.isUserSelectable }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
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

    func availableDomains() -> [(id: String, displayName: String)] {
        plugins.values
            .filter(\.isUserSelectable)
            .map { ($0.id, $0.displayName) }
            .sorted { lhs, rhs in
                if lhs.id == SoftwareDomain.defaultID { return true }
                if rhs.id == SoftwareDomain.defaultID { return false }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
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
