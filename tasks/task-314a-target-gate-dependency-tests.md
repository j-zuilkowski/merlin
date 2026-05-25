# Task 314a — TargetGateScanner Dependency-Following Tests (failing)

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin.
Task 313b complete: the discipline gate auto-installs at app launch.

When the gate went live (task 313) it blocked a commit because `merlin-discipline` —
built only as an implicit `dependencies:` entry of the `Merlin` target — is not named in
any `project.yml` scheme block, so `TargetGateScanner` flagged it as ungated. That is a
**false positive**: a target built transitively as a dependency of a scheme-built target
*is* compiled by that scheme. This task pins the corrected behavior; 314b implements it.

**This is a runtime-failure task.** The test compiles fine against the existing
`TargetGateScanner.scan` API and FAILS at runtime because today's scanner does not
follow `dependencies:`. It MUST be verified with `test`, not `build-for-testing`.

TDD coverage: a new test method on the existing `TargetGateScannerTests` (task 307a).

---

## Edit: MerlinTests/Unit/TargetGateScannerTests.swift
Add this method inside the `TargetGateScannerTests` class — it reuses the existing
private `makeTmpProject(projectYML:)` helper:

```swift
    /// A target built only as a dependency of a scheme-built target is reached
    /// transitively and must NOT be flagged as ungated.
    func testDependencyOnlyTargetIsTreatedAsGated() async throws {
        let proj = try makeTmpProject(projectYML: """
        name: Demo
        targets:
          App:
            type: application
            dependencies:
              - target: CoreLib
          CoreLib:
            type: framework
        schemes:
          App:
            build:
              targets:
                App: all
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let findings = await TargetGateScanner().scan(projectPath: proj.path)
        XCTAssertFalse(findings.contains { $0.targetName == "CoreLib" },
                       "a target built transitively as a dependency of a scheme-built "
                       + "target must not be flagged as ungated")
    }
```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/TargetGateScannerTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
```
Expected: BUILD SUCCEEDED; `testDependencyOnlyTargetIsTreatedAsGated` **FAILS**, the
other `TargetGateScannerTests` methods pass. Verified with `test` (not
`build-for-testing`) because the failure is at runtime.

## Commit
```
git add MerlinTests/Unit/TargetGateScannerTests.swift tasks/task-314a-target-gate-dependency-tests.md
git commit -m "Task 314a — TargetGateScanner dependency-following tests (failing)"
```
