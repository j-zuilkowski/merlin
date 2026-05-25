# Phase 67 — MCP Settings Section

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 66 complete: MemoriesSettingsView with enable/timeout/review.

Replace the stub `MCPSettingsView` in `SettingsWindowView.swift` with a real view that reads
`~/.merlin/mcp.json`, shows the list of configured servers, and lets the user add or remove
entries. Changes are saved back to `~/.merlin/mcp.json` immediately.

---

## Edit: Merlin/UI/Settings/SettingsWindowView.swift

Replace the stub `MCPSettingsView` struct with:

```swift
// MARK: - MCP Servers

struct MCPSettingsView: View {
    @State private var config: MCPConfig = MCPConfig(mcpServers: [:])
    @State private var isAddingServer = false
    @State private var newName = ""
    @State private var newCommand = ""
    @State private var newArgs = ""

    private var configURL: URL {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        return URL(fileURLWithPath: "\(home)/.merlin/mcp.json")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach(config.mcpServers.keys.sorted(), id: \.self) { name in
                    let serverConfig = config.mcpServers[name]!
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).bold()
                            Text(([serverConfig.command] + serverConfig.args).joined(separator: " "))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            config.mcpServers.removeValue(forKey: name)
                            save()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .onDelete { indexSet in
                    let keys = config.mcpServers.keys.sorted()
                    for index in indexSet {
                        config.mcpServers.removeValue(forKey: keys[index])
                    }
                    save()
                }
            }

            Divider()

            if isAddingServer {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Server name", text: $newName)
                    TextField("Command (e.g. npx -y @modelcontextprotocol/server-filesystem)", text: $newCommand)
                        .font(.system(.body, design: .monospaced))
                    TextField("Args (space-separated, optional)", text: $newArgs)
                        .font(.system(.body, design: .monospaced))
                    HStack {
                        Button("Cancel") {
                            isAddingServer = false
                            newName = ""
                            newCommand = ""
                            newArgs = ""
                        }
                        Spacer()
                        Button("Add") {
                            addServer()
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  newCommand.trimmingCharacters(in: .whitespaces).isEmpty)
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            } else {
                Button("Add Server…") {
                    isAddingServer = true
                }
                .padding()
            }
        }
        .task { load() }
    }

    private func load() {
        config = (try? MCPConfig.load(from: configURL.path)) ?? MCPConfig(mcpServers: [:])
    }

    private func save() {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        let dir = URL(fileURLWithPath: "\(home)/.merlin")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configURL)
        }
    }

    private func addServer() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        let cmd = newCommand.trimmingCharacters(in: .whitespaces)
        let argsArr = newArgs.split(separator: " ").map(String.init)
        config.mcpServers[name] = MCPServerConfig(command: cmd, args: argsArr)
        save()
        isAddingServer = false
        newName = ""
        newCommand = ""
        newArgs = ""
    }
}
```

Note: `MCPConfig.load(from:)` takes a `String` path, so call `configURL.path`.
`MCPConfig` needs to be `Encodable` — add `Encodable` conformance to `MCPConfig` in
`Merlin/MCP/MCPConfig.swift` if not already present (change `Codable` is already there).

---

## Edit: Merlin/MCP/MCPConfig.swift

Confirm `MCPConfig` and `MCPServerConfig` are both `Codable` (they already are). No changes needed
unless Codegen reports encoding not synthesized. If you see encoder errors, the existing `CodingKeys`
with `mcpServers` key handles it.

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD SUCCEEDED`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/UI/Settings/SettingsWindowView.swift
git commit -m "Phase 67 — MCPSettingsView: add/remove MCP server configs persisted to mcp.json"
```
