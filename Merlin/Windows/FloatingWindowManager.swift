import AppKit
import SwiftUI

@MainActor
final class FloatingWindowManager: ObservableObject {
    static let shared = FloatingWindowManager()

    private var windows: [UUID: NSWindow] = [:]
    private var trackers: [UUID: WindowCloseTracker] = [:]

    var openWindowCount: Int {
        windows.count
    }

    func open(session: Session, alwaysOnTop: Bool) {
        executeOnMain {
            self.openOnMain(session: session, alwaysOnTop: alwaysOnTop)
        }
    }

    func close(sessionID: UUID) {
        executeOnMain {
            self.closeOnMain(sessionID: sessionID)
        }
    }

    private func openOnMain(session: Session, alwaysOnTop: Bool) {
        if let window = windows[session.id] {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 480, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = session.title
        window.isReleasedWhenClosed = false
        if alwaysOnTop {
            window.level = .floating
        }

        let rootView: AnyView
        if isRuntimeWindowAvailable {
            rootView = AnyView(FloatingChatView(session: session, manager: self))
        } else {
            rootView = AnyView(FloatingWindowStubView(title: session.title))
        }

        window.contentView = NSHostingView(rootView: rootView)
        window.center()
        window.makeKeyAndOrderFront(nil)

        let tracker = WindowCloseTracker(sessionID: session.id, manager: self)
        window.delegate = tracker
        windows[session.id] = window
        trackers[session.id] = tracker
    }

    private func closeOnMain(sessionID: UUID) {
        windows[sessionID]?.close()
        remove(sessionID: sessionID)
    }

    fileprivate func remove(sessionID: UUID) {
        windows.removeValue(forKey: sessionID)
        trackers.removeValue(forKey: sessionID)
    }

    private var isRuntimeWindowAvailable: Bool {
        ProcessInfo.processInfo.processName != "xctest" &&
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    private func executeOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }
}

@MainActor
private final class WindowCloseTracker: NSObject, NSWindowDelegate {
    private let sessionID: UUID
    private weak var manager: FloatingWindowManager?

    init(sessionID: UUID, manager: FloatingWindowManager) {
        self.sessionID = sessionID
        self.manager = manager
    }

    func windowWillClose(_ notification: Notification) {
        manager?.remove(sessionID: sessionID)
    }
}

private struct FloatingWindowStubView: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Text("Floating window placeholder")
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FloatingChatView: View {
    let session: Session
    let manager: FloatingWindowManager

    var body: some View {
        VStack(spacing: 0) {
            ChatView()
            HStack {
                Spacer()
                Button("Close") {
                    manager.close(sessionID: session.id)
                }
                .padding(8)
            }
        }
    }
}
