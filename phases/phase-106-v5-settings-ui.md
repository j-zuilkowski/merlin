# Phase 106 — V5 Settings UI (role slots + domain selector + performance dashboard)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 105b complete: full V5 run loop wired.

This phase adds the Settings UI for V5: role slot assignment, active domain selector,
performance dashboard (per-model × task-type success rates), and degraded-mode indicator.
No new logic types — pure UI wired to existing V5 components.

---

## Write to: Merlin/Views/Settings/RoleSlotSettingsView.swift

```swift
import SwiftUI

/// Settings > Providers — role slot assignment panel.
/// Each slot maps to a provider ID from ProviderRegistry.
struct RoleSlotSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject private var registry: ProviderRegistry

    var body: some View {
        Form {
            Section("Role Slot Assignments") {
                Text("Assign providers to each capability slot. Unassigned slots fall back per the rules below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(AgentSlot.allCases, id: \.self) { slot in
                    slotRow(slot: slot)
                }
            }

            Section("Fallback Rules") {
                Text("• orchestrate → falls back to reason if unassigned\n• All slots → falls back to execute if unassigned\n• execute → NullProvider (no-op) if unassigned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Active Domain") {
                domainPicker
            }

            Section("Verification Commands") {
                LabeledContent("Build / Compile") {
                    TextField("e.g. xcodebuild -scheme MyApp build", text: settings.$verifyCommand)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                LabeledContent("Lint / Check") {
                    TextField("e.g. swiftlint", text: settings.$checkCommand)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Providers & Slots")
    }

    @ViewBuilder
    private func slotRow(_ slot: AgentSlot) -> some View {
        let binding = Binding<String>(
            get: { settings.slotAssignments[slot] ?? "" },
            set: { settings.slotAssignments[slot] = $0.isEmpty ? nil : $0 }
        )
        LabeledContent(slotLabel(slot)) {
            HStack {
                Picker("", selection: binding) {
                    Text("(unassigned)").tag("")
                    ForEach(registry.providers, id: \.id) { config in
                        Text(config.displayName.isEmpty ? config.id : config.displayName)
                            .tag(config.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)

                if let id = settings.slotAssignments[slot], !id.isEmpty,
                   settings.slotAssignments[slot] == nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("Degraded: \(slotLabel(slot)) slot provider unavailable — critic may be skipped")
                }
            }
        }
    }

    private func slotLabel(_ slot: AgentSlot) -> String {
        switch slot {
        case .execute:     return "Execute (fast/local)"
        case .reason:      return "Reason (thinking/critic)"
        case .orchestrate: return "Orchestrate (planner)"
        case .vision:      return "Vision"
        }
    }

    private var domainPicker: some View {
        LabeledContent("Active Domain") {
            Picker("", selection: settings.$activeDomainID) {
                Text("Software Development").tag("software")
                // Future domains added here as they register
            }
            .labelsHidden()
            .frame(maxWidth: 260)
        }
    }
}
```

---

## Write to: Merlin/Views/Settings/PerformanceDashboardView.swift

```swift
import SwiftUI

/// Settings > Providers — per-model performance breakdown.
/// Shows success rates, sample counts, trends, and addendum variant comparison.
struct PerformanceDashboardView: View {
    @State private var profiles: [ModelPerformanceProfile] = []

    var body: some View {
        Group {
            if profiles.isEmpty {
                ContentUnavailableView(
                    "No performance data yet",
                    systemImage: "chart.bar",
                    description: Text("Data accumulates after 30 tasks per model × task type.")
                )
            } else {
                List {
                    ForEach(groupedByModel, id: \.key) { modelID, modelProfiles in
                        Section(header: Text(modelID).font(.headline)) {
                            ForEach(modelProfiles, id: \.taskType.name) { profile in
                                profileRow(profile)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Performance Dashboard")
        .task {
            profiles = await ModelPerformanceTracker.shared.allProfiles()
        }
    }

    private var groupedByModel: [(key: String, value: [ModelPerformanceProfile])] {
        Dictionary(grouping: profiles, by: \.modelID)
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, value: $0.value) }
    }

    @ViewBuilder
    private func profileRow(_ profile: ModelPerformanceProfile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.taskType.displayName)
                    .font(.body)
                if profile.isCalibrated {
                    Text("\(profile.sampleCount) tasks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("learning… (\(profile.sampleCount)/30)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if profile.isCalibrated {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(profile.successRate * 100))%")
                        .monospacedDigit()
                    trendLabel(profile.trend)
                }
            }
        }
    }

    @ViewBuilder
    private func trendLabel(_ trend: Trend) -> some View {
        switch trend {
        case .improving:
            Label("↑", systemImage: "arrow.up")
                .font(.caption)
                .foregroundStyle(.green)
        case .declining:
            Label("↓", systemImage: "arrow.down")
                .font(.caption)
                .foregroundStyle(.red)
        case .stable:
            Text("→")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

---

## Edit: settings navigation to add V5 sections

In `Merlin/Views/Settings/SettingsWindowView.swift` (or equivalent), add to the navigation list:
```swift
NavigationLink("Providers & Slots", destination: RoleSlotSettingsView())
NavigationLink("Performance Dashboard", destination: PerformanceDashboardView())
```

---

## project.yml additions

```yaml
- Merlin/Views/Settings/RoleSlotSettingsView.swift
- Merlin/Views/Settings/PerformanceDashboardView.swift
```

Then:
```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED; zero warnings. Visual inspection: Settings > Providers & Slots panel shows slot pickers; Performance Dashboard shows "No data yet" on first launch.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Views/Settings/RoleSlotSettingsView.swift \
        Merlin/Views/Settings/PerformanceDashboardView.swift \
        Merlin/Views/Settings/SettingsWindowView.swift \
        project.yml
git commit -m "Phase 106 — V5 Settings UI (role slot assignment + domain selector + performance dashboard)"
```
