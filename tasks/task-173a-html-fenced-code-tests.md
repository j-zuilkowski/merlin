# Task 173a — ConversationHTMLRendererTests: fenced code block (failing — pre-existing)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 172b complete: ContextManager standalone tool message compaction fix.

## Problem

Two `ConversationHTMLRendererTests` tests fail because `markdownToHTML` has a
double-pass bug: it first calls `fencedCodeBlockPattern.stringByReplacingMatches`
with `withTemplate: "$1"` which replaces the ENTIRE fenced block with just the
language name string. Then `replaceFencedCodeBlocks` runs on the already-mangled
string and finds no fenced blocks to convert.

Result: `\`\`\`swift\ncode\n\`\`\`` becomes `"swift"` (just the language tag).

Failing tests:
- `testFencedCodeBlockConverted`
- `testLanguageTagAddedToCodeBlock`

Root cause in `Merlin/Views/Chat/ConversationHTMLRenderer.swift` ~line 90:
```swift
result = fencedCodeBlockPattern.stringByReplacingMatches(
    in: result,
    range: NSRange(result.startIndex..., in: result),
    withTemplate: "$1"   // destroys the fenced block before replaceFencedCodeBlocks can run
)
```

## Existing test file

`MerlinTests/Unit/ConversationHTMLRendererTests.swift` — already committed.

## Verify (current state — expected FAILING)

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'ConversationHTMLRenderer.*failed|BUILD' | head -10
```

Expected: `testFencedCodeBlockConverted` and `testLanguageTagAddedToCodeBlock` fail.

## Commit

```bash
cd ~/Documents/localProject/merlin
git add tasks/task-173a-html-fenced-code-tests.md
git commit -m "Task 173a — ConversationHTMLRenderer fenced code failure documented"
```
