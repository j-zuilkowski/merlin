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
            "Completed Jobs",
            "Progress History",
            "Artifacts",
            "Diagnostics",
            "Approvals",
            "Reports",
        ])
    }
}
