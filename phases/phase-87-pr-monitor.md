# Phase 87 — PRMonitor: Wire Into AppState

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 86 complete: ToolbarActionStore wired.

`PRMonitor` exists but is never instantiated. Wire it into `AppState`: start polling when a
GitHub token is available, and post a macOS notification when a PR's CI checks change state.
The monitor reads its token from `ConnectorCredentials`.

---

## Edit: Merlin/App/AppState.swift

Add a property:

```swift
    let prMonitor = PRMonitor()
```

After `engine` is created in `init`, start the monitor if a GitHub token is configured:

```swift
        Task {
            if let token = ConnectorCredentials.retrieve(service: "github"), !token.isEmpty {
                await prMonitor.startPolling(token: token, projectPath: projectPath)
            }
        }
```

Add a method to restart polling (called when the user saves a new GitHub token in Settings):

```swift
    func restartPRMonitor() {
        Task {
            prMonitor.stop()
            if let token = ConnectorCredentials.retrieve(service: "github"), !token.isEmpty {
                await prMonitor.startPolling(token: token, projectPath: projectPath)
            }
        }
    }
```

---

## Edit: Merlin/Views/Settings/ProviderSettingsView.swift (or ConnectorsSettingsView)

In `ConnectorsSettingsView.save()`, after saving the GitHub token, call:

```swift
        // Restart PR monitor with new token (AppState is a singleton via @EnvironmentObject)
        // Use NotificationCenter to decouple:
        NotificationCenter.default.post(name: .merlinGitHubTokenChanged, object: nil)
```

Add to `Notification.Name` extension in `AppState.swift`:

```swift
    static let merlinGitHubTokenChanged = Notification.Name("com.merlin.githubTokenChanged")
```

In `AppState.init`, observe this notification:

```swift
        NotificationCenter.default.addObserver(
            forName: .merlinGitHubTokenChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restartPRMonitor()
        }
```

---

## Check: Merlin/Connectors/PRMonitor.swift

Read the existing `PRMonitor.swift` to confirm the method signatures. If `startPolling(token:projectPath:)`
does not match, adjust the call site above to use the actual API. Also ensure `stop()` exists.
If `PRMonitor` requires a `RepoInfo` parameter instead of `projectPath`, parse the git remote
from `projectPath` using:

```swift
    private func repoInfoFromGit(projectPath: String) -> RepoInfo? {
        let result = try? ShellTool.runSync(command: "git -C \(projectPath) remote get-url origin")
        guard let url = result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
              let match = url.range(of: #"github\.com[:/](.+)/(.+?)(?:\.git)?$"#, options: .regularExpression) else {
            return nil
        }
        // parse owner/repo from match
        return nil  // implement as needed
    }
```

Use the actual PRMonitor API without adding wrapper complexity — read the file first.

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
git add Merlin/App/AppState.swift \
        Merlin/UI/Settings/SettingsWindowView.swift
git commit -m "Phase 87 — PRMonitor wired into AppState; starts polling when GitHub token is present"
```
