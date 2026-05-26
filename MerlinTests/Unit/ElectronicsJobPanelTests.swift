import XCTest
import SwiftUI
@testable import Merlin

@MainActor
final class ElectronicsJobPanelTests: XCTestCase {
    func testPanelTypeExistsWithOperationalSections() {
        let store = ElectronicsJobStore()
        _ = ElectronicsJobPanelView(store: store)

        XCTAssertEqual(ElectronicsJobPanelView.sectionLabels, [
            "Backend Health",
            "Jobs",
            "Progress",
            "Artifacts",
            "Diagnostics",
            "Approvals",
            "Reports",
        ])
    }
}
