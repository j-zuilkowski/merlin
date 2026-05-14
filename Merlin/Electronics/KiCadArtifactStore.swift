import Foundation

struct KiCadArtifactStore {
    let root: String
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(root: String) {
        self.root = root
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    var electronicsRootPath: String {
        root + "/.merlin/electronics"
    }

    func artifactID(designId: String, artifactKind: String) -> String {
        "\(designId)::\(artifactKind)"
    }

    func artifactPath(designId: String, artifactKind: String) -> String {
        electronicsRootPath + "/\(designId)/\(artifactKind).json"
    }

    func save<T: Codable>(_ artifact: T,
                          designId: String,
                          artifactKind: String) throws -> String {
        let data = try encoder.encode(artifact)
        let finalPath = artifactPath(designId: designId, artifactKind: artifactKind)
        let finalURL = URL(fileURLWithPath: finalPath)

        let directoryURL = finalURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let tempURL = directoryURL.appendingPathComponent(".\(artifactKind).tmp.\(UUID().uuidString)")
        try data.write(to: tempURL, options: .atomic)

        _ = try? fileManager.removeItem(at: finalURL)
        try fileManager.moveItem(at: tempURL, to: finalURL)

        return finalPath
    }

    func load<T: Codable>(_ type: T.Type,
                          designId: String,
                          artifactKind: String) throws -> T {
        let path = artifactPath(designId: designId, artifactKind: artifactKind)
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try decoder.decode(type, from: data)
    }
}
