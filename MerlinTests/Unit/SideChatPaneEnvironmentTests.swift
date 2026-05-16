import XCTest
import SwiftUI
@testable import Merlin

/// Regression guard for the v2.2.4 crash where `SideChatPane` rendered `ChatView`
/// without injecting a `ChatViewModel`, tripping SwiftUI's missing-`@EnvironmentObject`
/// fatalError (`EnvironmentObject.error()`) the first time the pane was made visible.
///
/// Hosting the pane with `isVisible: true` and forcing a layout pass walks the exact
/// code path from the crash report (`layoutSubtreeIfNeeded` -> `NSHostingView.layout`
/// -> `ChatView.body` -> `ChatView.messageList`), which resolves every
/// `@EnvironmentObject` `ChatView` declares. A missing one aborts this test.
@MainActor
final class SideChatPaneEnvironmentTests: XCTestCase {

    func testVisibleSideChatPaneRendersWithoutMissingEnvironmentObject() {
        var isVisible = true
        let binding = Binding(get: { isVisible }, set: { isVisible = $0 })
        let pane = SideChatPane(isVisible: binding, projectPath: "")

        let host = NSHostingController(rootView: pane)
        host.loadView()
        host.view.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
        host.view.layoutSubtreeIfNeeded()

        XCTAssertNotNil(host.view)
    }
}
