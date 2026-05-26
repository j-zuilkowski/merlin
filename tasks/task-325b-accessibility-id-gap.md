# Task 325b — AccessibilityID Gap-Fill Implementation

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 325a complete: failing `AccessibilityIDCoverageTests.testTask325IdentifiersAreDeclared`.

Adds the 12 missing `AccessibilityID` constants (W5 surface-census §1.2) and applies
`.accessibilityIdentifier(...)` to the 12 controls so XCUITest can reach them. Six files.

---

## 1. Edit: Merlin/Support/AccessibilityID.swift

Add this section immediately **before the closing `}`** of `enum AccessibilityID`
(after the last existing constant, `calibrationApplyAllButton`):
```swift

    // MARK: - Surface-census gap fill (task 325)

    public static let workspaceToggleDiffButton = "workspace-toggle-diff-button"
    public static let workspaceToggleFileButton = "workspace-toggle-file-button"
    public static let workspaceToggleTerminalButton = "workspace-toggle-terminal-button"
    public static let workspaceTogglePreviewButton = "workspace-toggle-preview-button"
    public static let workspaceToggleSideChatButton = "workspace-toggle-side-chat-button"
    public static let workspaceToggleMemoriesButton = "workspace-toggle-memories-button"
    public static let screenPreviewToggleButton = "screen-preview-toggle-button"
    public static let previewPaneCloseButton = "preview-pane-close-button"
    public static let toolRequirementInstallButton = "tool-requirement-install-button"
    public static let toolRequirementCancelButton = "tool-requirement-cancel-button"
    public static let toolRequirementDoneButton = "tool-requirement-done-button"
    public static let performanceAdvisoryApplyButtonPrefix = "performance-advisory-apply-button-"
```

## 2. Edit: Merlin/Views/WorkspaceView.swift

Replace the whole `toolbarContent` computed property — adds one
`.accessibilityIdentifier(...)` per toggle:
```swift
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { layout.showDiffPane.toggle() } label: {
                Label("Staged Changes", systemImage: "arrow.triangle.branch")
            }
            .buttonStyle(.bordered)
            .tint(layout.showDiffPane ? .accentColor : .secondary)
            .help("Toggle staged changes")
            .accessibilityIdentifier(AccessibilityID.workspaceToggleDiffButton)

            Button { layout.showFilePane.toggle() } label: {
                Label("File Viewer", systemImage: "doc.text")
            }
            .buttonStyle(.bordered)
            .tint(layout.showFilePane ? .accentColor : .secondary)
            .help("Toggle file viewer")
            .accessibilityIdentifier(AccessibilityID.workspaceToggleFileButton)

            Button { layout.showTerminalPane.toggle() } label: {
                Label("Terminal", systemImage: "terminal")
            }
            .buttonStyle(.bordered)
            .tint(layout.showTerminalPane ? .accentColor : .secondary)
            .help("Toggle terminal")
            .accessibilityIdentifier(AccessibilityID.workspaceToggleTerminalButton)

            Button { layout.showPreviewPane.toggle() } label: {
                Label("Preview", systemImage: "eye")
            }
            .buttonStyle(.bordered)
            .tint(layout.showPreviewPane ? .accentColor : .secondary)
            .help("Toggle preview")
            .accessibilityIdentifier(AccessibilityID.workspaceTogglePreviewButton)

            Button { layout.showSideChat.toggle() } label: {
                Label("Side Chat", systemImage: "bubble.right")
            }
            .buttonStyle(.bordered)
            .tint(layout.showSideChat ? .accentColor : .secondary)
            .help("Toggle side chat")
            .accessibilityIdentifier(AccessibilityID.workspaceToggleSideChatButton)

            Button { showMemoriesWindow = true } label: {
                Label("Memories", systemImage: "brain")
            }
            .buttonStyle(.bordered)
            .help("Review memories")
            .accessibilityIdentifier(AccessibilityID.workspaceToggleMemoriesButton)
        }
    }
```

## 3. Edit: Merlin/Views/ScreenPreviewView.swift

In `header`, the `Button { … } label: { … }` ends with `.buttonStyle(.plain)`. Append:
```swift
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.screenPreviewToggleButton)
```

## 4. Edit: Merlin/Views/PreviewPane.swift

In `header`, the close `Button` ends with `.help("Close preview")`. Append:
```swift
                .buttonStyle(.borderless)
                .help("Close preview")
                .accessibilityIdentifier(AccessibilityID.previewPaneCloseButton)
```

## 5. Edit: Merlin/Tools/ToolRequirementCoordinator.swift

In `ToolRequirementSheet.body`, add an identifier to each of the three buttons:
```swift
                HStack {
                    Button("Install with Homebrew") {
                        Task { await coordinator.installPending() }
                    }
                    .disabled(coordinator.isInstalling)
                    .accessibilityIdentifier(AccessibilityID.toolRequirementInstallButton)
                    Button("Cancel") {
                        coordinator.pending = nil
                    }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier(AccessibilityID.toolRequirementCancelButton)
                }
```
and:
```swift
                Button("Done") {
                    coordinator.pending = nil
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(AccessibilityID.toolRequirementDoneButton)
```

## 6. Edit: Merlin/Views/AdvisoryRow.swift

The `Button("Fix this", action: onFix)` ends with `.controlSize(.small)`. Append a
prefix identifier keyed by the advisory's parameter name:
```swift
                        Button("Fix this", action: onFix)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityIdentifier(
                                AccessibilityID.performanceAdvisoryApplyButtonPrefix
                                + advisory.parameterName)
```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/AccessibilityIDCoverageTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:|warning:'
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
xcodebuild -scheme MerlinTests-Live build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: both `AccessibilityIDCoverageTests` pass; BUILD SUCCEEDED on both schemes,
zero warnings. (The XCUITest reachability of each newly-identified control is verified
by eval scenarios S7/S9/S11 — this task establishes the constants + applies them.)

## Commit
```
git add Merlin/Support/AccessibilityID.swift Merlin/Views/WorkspaceView.swift \
  Merlin/Views/ScreenPreviewView.swift Merlin/Views/PreviewPane.swift \
  Merlin/Tools/ToolRequirementCoordinator.swift Merlin/Views/AdvisoryRow.swift \
  tasks/task-325b-accessibility-id-gap.md
git commit -m "Task 325b — AccessibilityID gap-fill: the 12 controls task 306 missed"
```
