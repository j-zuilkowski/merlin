# Phase 74 — TerminalPane: Inline PTY Terminal

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 73 complete: FilePane view created.

Add `TerminalPane` — a SwiftUI view wrapping an `NSTextView` that runs a PTY shell via
`posix_openpt` / `login_tty`. The pane opens a login shell (`/bin/zsh -l`), streams output
into the text view, and sends key input back to the PTY master.

The pane is wired into `WorkspaceView` in phase 77. This phase only creates the view file
and the underlying `PTYSession` actor.

---

## Write to: Merlin/Views/TerminalPane.swift

```swift
import SwiftUI
import AppKit

struct TerminalPane: View {
    let workingDirectory: String

    var body: some View {
        TerminalNSViewRepresentable(workingDirectory: workingDirectory)
    }
}

private struct TerminalNSViewRepresentable: NSViewRepresentable {
    let workingDirectory: String

    func makeCoordinator() -> PTYCoordinator {
        PTYCoordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        textView.isEditable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.textColor
        textView.delegate = context.coordinator
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        context.coordinator.textView = textView
        context.coordinator.start(workingDirectory: workingDirectory)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

final class PTYCoordinator: NSObject, NSTextViewDelegate, @unchecked Sendable {
    weak var textView: NSTextView?
    private var masterFD: Int32 = -1
    private var readTask: Task<Void, Never>?

    func start(workingDirectory: String) {
        masterFD = posix_openpt(O_RDWR)
        guard masterFD >= 0 else { return }
        grantpt(masterFD)
        unlockpt(masterFD)

        guard let slaveName = pts_name(masterFD) else { return }
        let slaveFD = open(slaveName, O_RDWR)
        guard slaveFD >= 0 else { return }

        let pid = fork()
        if pid == 0 {
            setsid()
            login_tty(slaveFD)
            close(masterFD)
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            var env = ProcessInfo.processInfo.environment
            env["TERM"] = "xterm-256color"
            withCString(shell) { shellPtr in
                withCString(workingDirectory.isEmpty ? FileManager.default.currentDirectoryPath : workingDirectory) { dirPtr in
                    chdir(dirPtr)
                    execle(shellPtr, shellPtr, "-l", nil, env.map { "\($0.key)=\($0.value)" }.withUnsafeMutableBytes { _ in
                        UnsafeMutablePointer<UnsafePointer<CChar>?>(nil)
                    })
                }
            }
            exit(1)
        } else {
            close(slaveFD)
        }

        let fd = masterFD
        readTask = Task.detached { [weak self] in
            var buf = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = read(fd, &buf, buf.count)
                guard n > 0 else { break }
                let str = String(bytes: buf[..<n], encoding: .utf8) ?? String(bytes: buf[..<n], encoding: .isoLatin1) ?? ""
                await MainActor.run { [weak self] in
                    self?.append(str)
                }
            }
        }
    }

    private func pts_name(_ fd: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: 256)
        ptsname_r(fd, &buf, buf.count)
        return String(cString: buf)
    }

    @MainActor
    private func append(_ text: String) {
        guard let tv = textView else { return }
        let storage = tv.textStorage!
        let attrs: [NSAttributedString.Key: Any] = [
            .font: tv.font!,
            .foregroundColor: tv.textColor!
        ]
        storage.append(NSAttributedString(string: text, attributes: attrs))
        tv.scrollToEndOfDocument(nil)
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
        guard let str = replacementString, masterFD >= 0 else { return false }
        str.withCString { ptr in
            _ = write(masterFD, ptr, strlen(ptr))
        }
        return false
    }
}
```

Note on `execle` and environment passing: the inline env map with `withUnsafeMutableBytes` above
is a placeholder. Replace the exec call with a simpler approach using `execl` with the shell
directly and inherit the current process environment:

```swift
            // Replace the execle block with:
            var cwd = workingDirectory.isEmpty
                ? FileManager.default.currentDirectoryPath
                : workingDirectory
            chdir(cwd)
            execl(shell, shell, "-l", nil as UnsafePointer<CChar>?)
```

Use this simpler form — it inherits the parent process environment automatically.

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
git add Merlin/Views/TerminalPane.swift
git commit -m "Phase 74 — TerminalPane: PTY shell via posix_openpt, NSTextView output, key input forwarding"
```
