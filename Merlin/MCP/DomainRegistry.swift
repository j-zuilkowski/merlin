import Foundation

/// Runtime registry of domain plugins. One active domain at a time.
/// Multi-domain sessions are deferred.
actor DomainRegistry {

    static let shared = DomainRegistry()

    private var plugins: [String: any DomainPlugin] = [:]
    private var activeDomainID: String = "software"

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
        if activeDomainID == id {
            activeDomainID = "software"
        }
    }

    func setActiveDomain(id: String) {
        guard plugins[id] != nil else { return }
        activeDomainID = id
    }

    func activeDomain() -> any DomainPlugin {
        plugins[activeDomainID] ?? plugins["software"] ?? SoftwareDomain()
    }

    /// Returns task types for the active domain only. Multi-domain is deferred.
    func taskTypes() -> [DomainTaskType] {
        activeDomain().taskTypes
    }

    func plugin(for id: String) -> (any DomainPlugin)? {
        plugins[id]
    }
}
