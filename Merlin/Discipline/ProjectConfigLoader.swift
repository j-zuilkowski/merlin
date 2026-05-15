import Foundation

/// Reads and writes `.merlin/project.toml` for a given project root.
struct ProjectConfigLoader: Sendable {

    enum LoadError: Error, Sendable {
        case notFound(String)
        case parseFailed(String)
    }

    // MARK: - Path helpers

    private func configURL(projectPath: String) -> URL {
        URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".merlin")
            .appendingPathComponent("project.toml")
    }

    // MARK: - exists

    func exists(projectPath: String) -> Bool {
        FileManager.default.fileExists(atPath: configURL(projectPath: projectPath).path)
    }

    // MARK: - load

    func load(projectPath: String) async throws -> ProjectConfig {
        let url = configURL(projectPath: projectPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LoadError.notFound(url.path)
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        return try parseProjectTOML(text)
    }

    // MARK: - save

    func save(_ config: ProjectConfig, projectPath: String) async throws {
        let dotMerlin = URL(fileURLWithPath: projectPath).appendingPathComponent(".merlin")
        try FileManager.default.createDirectory(
            at: dotMerlin,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let toml = serialise(config)
        try toml.write(
            to: dotMerlin.appendingPathComponent("project.toml"),
            atomically: true,
            encoding: .utf8
        )
    }

    // MARK: - defaultConfig

    static func defaultConfig(adapter: String) -> ProjectConfig {
        ProjectConfig(
            adapter: adapter,
            adapterVersion: "1.0",
            disciplineLayers: ["soft_prompt", "pre_commit"],
            manualCoverageBaseline: 0,
            decayPerRelease: 10
        )
    }

    // MARK: - TOML parser (project.toml subset)

    private func parseProjectTOML(_ text: String) throws -> ProjectConfig {
        var kv: [String: String] = [:]
        var layers: [String] = []

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eqIdx = line.firstIndex(of: "=") else { continue }

            let key = line[line.startIndex..<eqIdx]
                .trimmingCharacters(in: .whitespaces)
            let rawVal = line[line.index(after: eqIdx)...]
                .trimmingCharacters(in: .whitespaces)

            if key == "discipline_layers" {
                let stripped = rawVal.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                layers = stripped
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
                    .filter { !$0.isEmpty }
            } else {
                let val = rawVal.hasPrefix("\"") && rawVal.hasSuffix("\"")
                    ? String(rawVal.dropFirst().dropLast())
                    : rawVal
                kv[key] = val
            }
        }

        guard let adapter = kv["adapter"] else {
            throw LoadError.parseFailed("missing 'adapter' field")
        }

        return ProjectConfig(
            adapter: adapter,
            adapterVersion: kv["adapter_version"] ?? "1.0",
            disciplineLayers: layers.isEmpty ? ["soft_prompt", "pre_commit"] : layers,
            manualCoverageBaseline: Int(kv["manual_coverage_baseline"] ?? "0") ?? 0,
            decayPerRelease: Int(kv["decay_per_release"] ?? "10") ?? 10
        )
    }

    // MARK: - TOML serialiser

    private func serialise(_ config: ProjectConfig) -> String {
        let layersStr = config.disciplineLayers
            .map { "\"\($0)\"" }
            .joined(separator: ", ")
        return """
        adapter = "\(config.adapter)"
        adapter_version = "\(config.adapterVersion)"
        discipline_layers = [\(layersStr)]
        manual_coverage_baseline = \(config.manualCoverageBaseline)
        decay_per_release = \(config.decayPerRelease)
        """
    }
}
