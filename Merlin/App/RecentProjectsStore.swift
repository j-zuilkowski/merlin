import Combine
import Foundation

@MainActor
final class RecentProjectsStore: ObservableObject {
    private static let key = "com.merlin.recentProjects"
    private static let maxEntries = 10

    @Published private(set) var projects: [ProjectRef] = []

    init() { load() }

    func touch(_ ref: ProjectRef) {
        var updated = ref
        updated.lastOpenedAt = Date()
        var list = projects.filter { $0.path != ref.path }
        list.insert(updated, at: 0)
        projects = Array(list.prefix(Self.maxEntries))
        save()
    }

    func remove(_ ref: ProjectRef) {
        projects.removeAll { $0.path == ref.path }
        save()
    }

    func clear() {
        projects = []
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([ProjectRef].self, from: data)
        else { return }
        projects = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
