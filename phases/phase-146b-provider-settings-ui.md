# Phase 146b — Provider Settings UI

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 146a complete: failing tests in place.

---

## Edit: Merlin/Providers/ProviderConfig.swift

### 1. Add `SlotPickerEntry` and `allSlotPickerEntries`

Add near the top of the file (after the imports, before `ProviderRegistry`):

```swift
/// A single selectable entry in the role-slot assignment picker.
struct SlotPickerEntry: Identifiable, Equatable, Sendable {
    /// The provider ID stored in `slotAssignments` — either a plain ID or `"backendID:modelID"`.
    let id: String
    /// Human-readable label shown in the picker.
    let displayName: String
    /// True for virtual `"backendID:modelID"` entries derived from loaded local models.
    let isVirtual: Bool
}
```

Add to `ProviderRegistry`:

```swift
    /// All entries that can be assigned to a role slot.
    /// Plain provider IDs come first (alphabetical by display name), followed by virtual
    /// entries grouped by backend and sorted by model name.
    var allSlotPickerEntries: [SlotPickerEntry] {
        var plain: [SlotPickerEntry] = []
        var virtual: [SlotPickerEntry] = []

        let enabled = providers.filter(\.isEnabled)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        for config in enabled {
            plain.append(SlotPickerEntry(id: config.id,
                                         displayName: config.displayName.isEmpty ? config.id : config.displayName,
                                         isVirtual: false))
            if let models = modelsByProviderID[config.id], !models.isEmpty {
                for model in models.sorted() {
                    let vid = "\(config.id):\(model)"
                    let vname = "\(config.displayName.isEmpty ? config.id : config.displayName) — \(model)"
                    virtual.append(SlotPickerEntry(id: vid, displayName: vname, isVirtual: true))
                }
            }
        }
        return plain + virtual
    }
```

### 2. Make `modelsByProviderID` writable from test code

Change:
```swift
    @Published private(set) var modelsByProviderID: [String: [String]] = [:]
```
to:
```swift
    @Published var modelsByProviderID: [String: [String]] = [:]
```

External write access is fine — the registry is `@MainActor`-bound and test setup needs it.

---

## Edit: Merlin/Views/Settings/ProviderSettingsView.swift

### 1. Add `isFetchingModels` state and Refresh button

Add to `ProviderSettingsView`:
```swift
    @State private var isFetchingModels = false
```

In the `Section("Providers")` header area, add a refresh button:
```swift
            Section {
                ForEach(registry.providers) { config in
                    // ... existing ProviderRow ...
                }
            } header: {
                HStack {
                    Text("Providers")
                    Spacer()
                    Button {
                        isFetchingModels = true
                        Task {
                            await registry.probeAndFetchModels()
                            await registry.fetchAllModels()
                            isFetchingModels = false
                        }
                    } label: {
                        if isFetchingModels {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Refresh Models", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isFetchingModels)
                }
            }
```

### 2. Use `registry.modelsByProviderID` in `ProviderRow`

This was already done in phase 143b. Confirm the call site reads:
```swift
                        availableModels: registry.modelsByProviderID[config.id] ?? [],
```

---

## Edit: Merlin/Views/Settings/RoleSlotSettingsView.swift

### Update `slotRow` Picker to use `allSlotPickerEntries`

Replace:
```swift
                Picker("", selection: binding) {
                    Text("(unassigned)").tag("")
                    ForEach(registry.providers, id: \.id) { config in
                        Text(config.displayName.isEmpty ? config.id : config.displayName)
                            .tag(config.id)
                    }
                }
```

With:
```swift
                Picker("", selection: binding) {
                    Text("(unassigned)").tag("")
                    ForEach(registry.allSlotPickerEntries) { entry in
                        Text(entry.displayName).tag(entry.id)
                    }
                }
```

### Update the warning indicator

The existing warning checks `registry.providers.contains(where: { $0.id == assignedID })`.
Update to also accept virtual IDs:

```swift
                if let assignedID = settings.slotAssignments[slot],
                   !assignedID.isEmpty,
                   registry.provider(for: assignedID) == nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("Provider '\(registry.displayName(for: assignedID))' is unavailable")
                }
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'SlotPickerEntries|passed|failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: all SlotPickerEntriesTests pass, BUILD SUCCEEDED, zero warnings.

## Commit
```bash
git add Merlin/Providers/ProviderConfig.swift \
        Merlin/Views/Settings/ProviderSettingsView.swift \
        Merlin/Views/Settings/RoleSlotSettingsView.swift
git commit -m "Phase 146b — Provider settings UI with dynamic model picker"
```
