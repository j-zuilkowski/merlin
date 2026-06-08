import AppKit
import SwiftUI
import XCTest
@testable import Merlin

@MainActor
final class FloatingWindowRuntimeTests: XCTestCase {

    private func closeTestWindow(_ window: NSWindow) {
        window.animationBehavior = .none
        window.orderOut(nil)
        window.contentView = nil
        window.delegate = nil
        window.close()
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }

    func test_testingRuntimeBuildsRealFloatingChatContainer() {
        var builtSession: Session?
        var builtManager: FloatingWindowManager?
        var capturedWindow: NSWindow?

        let manager = FloatingWindowManager(
            runtimeMode: .testing,
            windowFactory: { frame, styleMask in
                let window = NSWindow(
                    contentRect: frame,
                    styleMask: styleMask,
                    backing: .buffered,
                    defer: false
                )
                capturedWindow = window
                return window
            },
            rootViewFactory: { session, manager in
                builtSession = session
                builtManager = manager
                return AnyView(FloatingChatView(session: session, manager: manager))
            }
        )

        let session = Session.stub(title: "Floating Runtime")
        manager.open(session: session, alwaysOnTop: false)
        defer {
            manager.close(sessionID: session.id)
            if let capturedWindow {
                closeTestWindow(capturedWindow)
            }
        }

        XCTAssertEqual(builtSession?.id, session.id)
        XCTAssertTrue(builtManager === manager)
        XCTAssertEqual(manager.openWindowCount, 1)
        XCTAssertNotNil(capturedWindow?.contentView)
    }

    func test_openingFloatingSessionBindsTheSuppliedSession() {
        var boundSession: Session?
        var capturedWindow: NSWindow?

        let manager = FloatingWindowManager(
            runtimeMode: .testing,
            windowFactory: { frame, styleMask in
                let window = NSWindow(
                    contentRect: frame,
                    styleMask: styleMask,
                    backing: .buffered,
                    defer: false
                )
                capturedWindow = window
                return window
            },
            rootViewFactory: { session, manager in
                boundSession = session
                return AnyView(FloatingChatView(session: session, manager: manager))
            }
        )

        let session = Session.stub(title: "Session Binding")
        manager.open(session: session, alwaysOnTop: false)
        defer {
            manager.close(sessionID: session.id)
            if let capturedWindow {
                closeTestWindow(capturedWindow)
            }
        }

        XCTAssertEqual(boundSession?.id, session.id)
        XCTAssertEqual(capturedWindow?.title, session.title)
    }

    func test_closeRemovesWindowFromRegistry() {
        let manager = FloatingWindowManager(runtimeMode: .testing)
        let session = Session.stub(title: "Close Registry")

        manager.open(session: session, alwaysOnTop: false)
        defer { manager.close(sessionID: session.id) }
        XCTAssertEqual(manager.openWindowCount, 1)

        manager.close(sessionID: session.id)

        XCTAssertEqual(manager.openWindowCount, 0)
    }

    func test_alwaysOnTopUsesFloatingWindowLevel() {
        var capturedWindow: NSWindow?

        let manager = FloatingWindowManager(
            runtimeMode: .testing,
            windowFactory: { frame, styleMask in
                let window = NSWindow(
                    contentRect: frame,
                    styleMask: styleMask,
                    backing: .buffered,
                    defer: false
                )
                capturedWindow = window
                return window
            }
        )

        let session = Session.stub(title: "Always On Top")
        manager.open(session: session, alwaysOnTop: true)
        defer {
            manager.close(sessionID: session.id)
            if let capturedWindow {
                closeTestWindow(capturedWindow)
            }
        }

        XCTAssertEqual(capturedWindow?.level, .floating)
    }
}

private extension Session {
    static func stub(title: String) -> Session {
        Session(title: title, messages: [])
    }
}
