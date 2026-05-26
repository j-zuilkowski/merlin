import Foundation

@MainActor
struct WorkspaceArtifactStore {
    let runtime: WorkspaceRuntime
    private var metadataURL: URL {
        runtime.stateRootURL.appendingPathComponent("artifacts.json")
    }

    func save(_ artifact: WorkspaceArtifactRef) throws {
        var artifacts = try loadAll()
        artifacts.removeAll { $0.id == artifact.id }
        artifacts.append(artifact)
        try FileManager.default.createDirectory(at: metadataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try WorkspaceJSON.encoder.encode(artifacts).write(to: metadataURL, options: .atomic)
    }

    func loadAll() throws -> [WorkspaceArtifactRef] {
        guard FileManager.default.fileExists(atPath: metadataURL.path) else { return [] }
        let data = try Data(contentsOf: metadataURL)
        return try WorkspaceJSON.decoder.decode([WorkspaceArtifactRef].self, from: data)
    }
}
