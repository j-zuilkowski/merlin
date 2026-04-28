// HelpWindowManager — holds strong references to open help windows.
//
// NSWindow created programmatically must be retained by someone other than
// the run loop. Without this manager the window is deallocated the moment
// openHelp() returns, causing a crash when the user later closes it.
import AppKit
import SwiftUI

@MainActor
final class HelpWindowManager: NSObject, NSWindowDelegate {
    static let shared = HelpWindowManager()

    private var windows: [NSWindow] = []

    func open(_ document: HelpDocument) {
        // Bring existing window to front rather than opening a duplicate
        if let existing = windows.first(where: { $0.title == document.title }) {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let hostView = NSHostingView(
            rootView: NavigationStack {
                HelpWindowView(document: document)
            }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = document.title
        window.contentView = hostView
        window.delegate = self
        // Prevent the ARC double-release crash: by default NSWindows created
        // programmatically send an extra release on close; under ARC this is a
        // double-free when our windows array also releases the strong reference.
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        windows.append(window)   // ← keeps the window alive
    }

    // Remove from the strong-reference array only after the window has closed.
    nonisolated func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        Task { @MainActor in
            self.windows.removeAll { $0 === window }
        }
    }
}
