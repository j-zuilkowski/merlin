# Task 173b — Fix: remove double-pass fenced code block bug in markdownToHTML

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 173a complete: ConversationHTMLRenderer fenced code failures documented.

## Root Cause

`ConversationHTMLRenderer.markdownToHTML` has two passes for fenced code blocks:

1. **Pass 1** (~line 90): `fencedCodeBlockPattern.stringByReplacingMatches(..., withTemplate: "$1")`
   This replaces the entire fenced block (e.g. ` ```swift\ncode\n``` `) with just the
   language name (`swift`). The comment says "NSRegularExpression template replacement
   doesn't support closures; use manual iteration instead." But the template IS applied
   and it DESTROYS the block before pass 2 can run.

2. **Pass 2** (~line 97): `result = replaceFencedCodeBlocks(in: result)`
   Runs on the already-mangled string. No fenced blocks remain to convert.

The `$1` template silently replaces all fenced blocks with the language name string.

## Fix

### Edit: `Merlin/Views/Chat/ConversationHTMLRenderer.swift`

**Find** (~line 89):
```swift
        // Fenced code blocks — must run before inline patterns to avoid mangling backticks
        result = fencedCodeBlockPattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "$1"   // replaced by the transform closure below
        )
        // NSRegularExpression template replacement doesn't support closures;
        // use manual iteration instead.
        result = replaceFencedCodeBlocks(in: result)
```

**Replace with**:
```swift
        // Fenced code blocks — must run before inline patterns to avoid mangling backticks.
        // replaceFencedCodeBlocks() uses manual NSRange iteration (not template replacement)
        // because NSRegularExpression.stringByReplacingMatches cannot call closures.
        result = replaceFencedCodeBlocks(in: result)
```

(Remove the `fencedCodeBlockPattern.stringByReplacingMatches` call entirely. It was a dead
first pass that destroyed fenced blocks before the real converter ran.)

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'ConversationHTMLRenderer.*passed|ConversationHTMLRenderer.*failed|BUILD' | head -10
```

Expected: BUILD SUCCEEDED; all ConversationHTMLRendererTests pass.

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Views/Chat/ConversationHTMLRenderer.swift \
        tasks/task-173b-html-fenced-code-fix.md
git commit -m "Task 173b — Fix: remove double-pass fenced code block bug in markdownToHTML"
```
