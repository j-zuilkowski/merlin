import XCTest
import SwiftUI
@testable import Merlin

@MainActor
final class ElectronicsJobPanelTests: XCTestCase {
    func testPanelTypeExistsWithOperationalSections() {
        let store = ElectronicsJobStore()
        _ = ElectronicsJobPanelView(store: store)

        XCTAssertEqual(ElectronicsJobPanelView.sectionLabels, [
            "Live Leaderboard",
            "Running Now",
            "Blocked Jobs",
            "Fab Ready",
            "Completed Jobs",
            "Progress History",
            "Evidence Gates",
            "Artifacts",
            "Diagnostics",
            "Approvals",
            "Reports",
        ])
    }
}
