# Phase 143b — Dynamic Model Fetch Implementation

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 143a complete: failing tests in place.

---

## Edit: Merlin/Providers/ProviderConfig.swift

### 1. Add injectable `URLSession` and `initialProviders` to `ProviderRegistry.init`

Replace the existing `init(persistURL:)`:

```swift
    init(persistURL: URL = ProviderRegistry.defaultPersistURL,
         session: URLSession = .shared,
         initialProviders: [ProviderConfig]? = nil) {
        self.persistURL = persistURL
        self.session = session
        if let initial = initialProviders {
            providers = initial
            activeProviderID = initial.first?.id ?? "deepseek"
        } else if let loaded = Self.load(from: persistURL) {
            providers = loaded.providers
            activeProviderID = loaded.activeProviderID
        } else {
            providers = Self.defaultProviders
            activeProviderID = "deepseek"
        }
        keyedProviderIDs = Set(Self.loadKeys().keys)
        for id in keyedProviderIDs {
            if let i = providers.firstIndex(where: { $0.id == id && !$0.isLocal && !$0.isEnabled }) {
                providers[i].isEnabled = true
            }
        }
    }
```

Add `private let session: URLSession` as a stored property alongside `persistURL`.

### 2. Add `@Published var modelsByProviderID`

After `@Published var availabilityByID`:
```swift
    @Published private(set) var modelsByProviderID: [String: [String]] = [:]
```

### 3. Delete `knownModels`

Remove the entire `static let knownModels: [String: [String]]` declaration and its contents.

### 4. Add `fetchModels(for:) async -> [String]`

```swift
    func fetchModels(for config: ProviderConfig) async -> [String] {
        guard config.isEnabled else { return [] }

        // Anthropic uses a different auth header and slightly different response shape
        if config.kind == .anthropic {
            return await fetchAnthropicModels(config: config)
        }

        guard let url = URL(string: config.baseURL)?.appendingPathComponent("models") else {
            return []
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        if !config.isLocal, let key = readAPIKey(for: config.id), !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            struct Model: Decodable { var id: String }
            struct Response: Decodable { var data: [Model] }
            return try JSONDecoder().decode(Response.self, from: data).data.map(\.id)
        } catch {
            return []
        }
    }

    private func fetchAnthropicModels(config: ProviderConfig) async -> [String] {
        guard let url = URL(string: "https://api.anthropic.com/v1/models") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        if let key = readAPIKey(for: config.id), !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue(AnthropicProvider.anthropicVersion,
                             forHTTPHeaderField: "anthropic-version")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            struct Model: Decodable { var id: String }
            struct Response: Decodable { var data: [Model] }
            return try JSONDecoder().decode(Response.self, from: data).data.map(\.id)
        } catch {
            return []
        }
    }
```

### 5. Add `fetchAllModels() async`

```swift
    func fetchAllModels() async {
        await withTaskGroup(of: (String, [String]).self) { group in
            for config in providers where config.isEnabled {
                group.addTask { [weak self] in
                    guard let self else { return (config.id, []) }
                    let models = await self.fetchModels(for: config)
                    return (config.id, models)
                }
            }
            for await (id, models) in group where !models.isEmpty {
                modelsByProviderID[id] = models
            }
        }
    }
```

### 6. Replace `probeLocalProviders()` with `probeAndFetchModels()`

Delete the existing `probeLocalProviders()` function and replace with:

```swift
    /// Probes availability and fetches the model list for every enabled local provider.
    /// Sets both `availabilityByID` and `modelsByProviderID`.
    func probeAndFetchModels() async {
        await withTaskGroup(of: (String, Bool, [String]).self) { group in
            for config in providers where config.isLocal && config.isEnabled {
                group.addTask { [weak self] in
                    guard let self else { return (config.id, false, []) }
                    // Health check
                    let available: Bool
                    if let healthURL = URL(string: config.baseURL)?
                        .deletingLastPathComponent()
                        .appendingPathComponent("health") {
                        var req = URLRequest(url: healthURL)
                        req.timeoutInterval = 2
                        let status = (try? await self.session.data(for: req))
                            .flatMap { $0.1 as? HTTPURLResponse }?.statusCode
                        available = status.map { (200...299).contains($0) } ?? false
                    } else {
                        available = false
                    }
                    // Model list (only worth attempting if the server responded)
                    let models = available ? await self.fetchModels(for: config) : []
                    return (config.id, available, models)
                }
            }
            for await (id, available, models) in group {
                availabilityByID[id] = available
                if !models.isEmpty { modelsByProviderID[id] = models }
            }
        }
    }
```

---

## Edit: Merlin/App/AppState.swift

### Update all call sites

1. Replace `await registry.probeLocalProviders()` with `await registry.probeAndFetchModels()`.
2. After `probeAndFetchModels()`, also call `await registry.fetchAllModels()` to populate remote providers too.

Find:
```swift
        Task { await registry.probeLocalProviders() }
```
Replace with:
```swift
        Task {
            await registry.probeAndFetchModels()
            await registry.fetchAllModels()
        }
```

Also add the same call in any `onChange` handler that currently calls `probeLocalProviders`.

---

## Edit: Merlin/UI/Settings/SettingsWindowView.swift and Merlin/Views/Settings/ProviderSettingsView.swift

Replace every occurrence of:
```swift
ProviderRegistry.knownModels[...
```
with:
```swift
registry.modelsByProviderID[...
```

Both files use this pattern. After this change, local providers that return multiple models from
`/v1/models` will show all of them in the picker immediately — no further UI changes needed here
(those come in phase 146).

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'DynamicModelFetch|passed|failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: all DynamicModelFetchTests pass, BUILD SUCCEEDED, zero warnings.

## Commit
```bash
git add Merlin/Providers/ProviderConfig.swift \
        Merlin/App/AppState.swift \
        Merlin/UI/Settings/SettingsWindowView.swift \
        Merlin/Views/Settings/ProviderSettingsView.swift
git commit -m "Phase 143b — Dynamic model fetch"
```
