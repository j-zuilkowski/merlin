import AppKit
import SwiftUI

@MainActor
final class FloatingWindowManager: ObservableObject {
    static let shared = FloatingWindowManager()

    enum RuntimeMode: Sendable {
        case live
        case testing
    }

    private var windows: [UUID: NSWindow] = [:]
    private var trackers: [UUID: WindowCloseTracker] = [:]
    private let runtimeMode: RuntimeMode
    private let windowFactory: @MainActor (NSRect, NSWindow.StyleMask) -> NSWindow
    private let rootViewFactory: @MainActor (Session, FloatingWindowManager) -> AnyView

    init(
        runtimeMode: RuntimeMode = .live,
        windowFactory: @escaping @MainActor (NSRect, NSWindow.StyleMask) -> NSWindow = FloatingWindowManager.makeDefaultWindow,
        rootViewFactory: @escaping @MainActor (Session, FloatingWindowManager) -> AnyView = FloatingWindowManager.makeDefaultRootView
    ) {
        self.runtimeMode = runtimeMode
        self.windowFactory = windowFactory
        self.rootViewFactory = rootViewFactory
    }

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
            configure(window: window, session: session, alwaysOnTop: alwaysOnTop)
            present(window)
            return
        }

        let window = windowFactory(
            NSRect(x: 100, y: 100, width: 480, height: 640),
            [.titled, .closable, .resizable, .miniaturizable]
        )
        configure(window: window, session: session, alwaysOnTop: alwaysOnTop)
        window.contentView = NSHostingView(rootView: rootViewFactory(session, self))
        present(window)

        let tracker = WindowCloseTracker(sessionID: session.id, manager: self)
        window.delegate = tracker
        windows[session.id] = window
        trackers[session.id] = tracker
    }

    private func configure(window: NSWindow, session: Session, alwaysOnTop: Bool) {
        window.title = session.title
        window.isReleasedWhenClosed = false
        window.level = alwaysOnTop ? .floating : .normal
    }

    private func closeOnMain(sessionID: UUID) {
        windows[sessionID]?.close()
        remove(sessionID: sessionID)
    }

    fileprivate func remove(sessionID: UUID) {
        windows.removeValue(forKey: sessionID)
        trackers.removeValue(forKey: sessionID)
    }

    private func present(_ window: NSWindow) {
        guard runtimeMode == .live else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func executeOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }

    private static func makeDefaultWindow(contentRect: NSRect, styleMask: NSWindow.StyleMask) -> NSWindow {
        NSWindow(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
    }

    private static func makeDefaultRootView(session: Session, manager: FloatingWindowManager) -> AnyView {
        AnyView(FloatingChatView(session: session, manager: manager))
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

struct FloatingChatView: View {
    let session: Session
    let manager: FloatingWindowManager
    @StateObject private var sessionManager: SessionManager
    @State private var liveSession: LiveSession?

    init(session: Session, manager: FloatingWindowManager) {
        self.session = session
        self.manager = manager
        let projectRef = ProjectRef(
            path: "",
            displayName: session.title,
            lastOpenedAt: session.createdAt
        )
        _sessionManager = StateObject(wrappedValue: SessionManager(projectRef: projectRef))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let liveSession {
                ChatView()
                    .environmentObject(liveSession.appState)
                    .environmentObject(liveSession.skillsRegistry)
                    .environmentObject(liveSession.appState.registry)
                    .environmentObject(sessionManager)
                    .environmentObject(liveSession.chatViewModel)
            } else {
                VStack(spacing: 10) {
                    Text(session.title)
                        .font(.headline)
                    ProgressView("Loading chat session...")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Spacer()
                Button("Close") {
                    manager.close(sessionID: session.id)
                }
                .padding(8)
            }
        }
        .task {
            guard liveSession == nil else { return }
            liveSession = await sessionManager.restore(session: session)
        }
    }
}
