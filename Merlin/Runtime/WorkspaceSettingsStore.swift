import Foundation

@MainActor
struct WorkspaceSettingsStore {
    let runtime: WorkspaceRuntime

    func save(_ namespace: WorkspaceSettingsNamespace) async throws {
        let schemas = await runtime.bus.registeredSettingsSchemas()
        let secretKeys = Set(
            schemas
                .first(where: { $0.namespace == namespace.namespace })?
                .fields
                .filter(\.isSecret)
                .map(\.key) ?? []
        )
        let persisted = namespace.values.filter { !secretKeys.contains($0.key) }
        let lines = persisted
            .sorted { $0.key < $1.key }
            .map { key, value in "\(key) = \(tomlValue(value))" }
            .joined(separator: "\n")
        let url = runtime.settingsURL(namespace: namespace.namespace)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (lines + "\n").write(to: url, atomically: true, encoding: .utf8)
        await runtime.bus.publish(WorkspaceMessageEvent(
            id: UUID(),
            requestID: nil,
            address: WorkspaceMessageAddress(namespace: namespace.namespace, capability: "settings.changed"),
            origin: nil,
            kind: .settingsChanged,
            payload: .jsonString(#"{"namespace":"\#(namespace.namespace)"}"#)
        ))
    }

    func load(namespace: String) throws -> WorkspaceSettingsNamespace {
        let url = runtime.settingsURL(namespace: namespace)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return WorkspaceSettingsNamespace(namespace: namespace, values: [:])
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        var values: [String: WorkspaceSettingsValue] = [:]
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.isEmpty == false, line.hasPrefix("#") == false,
                  let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            values[key] = parseTomlValue(String(value))
        }
        return WorkspaceSettingsNamespace(namespace: namespace, values: values)
    }

    private func tomlValue(_ value: WorkspaceSettingsValue) -> String {
        switch value {
        case .string(let string):
            return "\"\(string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
        case .integer(let integer):
            return "\(integer)"
        case .double(let double):
            return "\(double)"
        case .boolean(let boolean):
            return boolean ? "true" : "false"
        }
    }

    private func parseTomlValue(_ value: String) -> WorkspaceSettingsValue {
        if value == "true" { return .boolean(true) }
        if value == "false" { return .boolean(false) }
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            var text = value
            text.removeFirst()
            text.removeLast()
            return .string(text.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\"))
        }
        if let integer = Int(value) { return .integer(integer) }
        if let double = Double(value) { return .double(double) }
        return .string(value)
    }
}
