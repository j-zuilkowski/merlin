import XCTest
@testable import Merlin

final class SlotStatusResolverTests: XCTestCase {

    func testNoAssignmentsReturnsFourGreyNotConfiguredRows() {
        let resolver = SlotStatusResolver { _ in "unused" }

        let rows = resolver.rows(slotAssignments: [:])

        XCTAssertEqual(rows.map(\.id), [.execute, .reason, .orchestrate, .vision])
        XCTAssertEqual(rows.count, 4)
        XCTAssertTrue(rows.allSatisfy { $0.value == "Not configured" })
        XCTAssertTrue(rows.allSatisfy { $0.state == .notConfigured })
    }

    func testProviderInventoryDoesNotPopulateRows() {
        let resolver = SlotStatusResolver { id in
            switch id {
            case "deepseek": return "DeepSeek"
            case "llamacpp:qwen3-coder": return "llama.cpp — qwen3-coder"
            default: return id
            }
        }

        let rows = resolver.rows(slotAssignments: [:])

        XCTAssertEqual(rows.map(\.value), Array(repeating: "Not configured", count: 4))
    }

    func testPartialAssignmentsOnlyPopulateAssignedRows() {
        let resolver = SlotStatusResolver { id in id == "deepseek" ? "DeepSeek" : id }
        let rows = resolver.rows(slotAssignments: [.execute: "deepseek"])

        XCTAssertEqual(rows.first(where: { $0.id == .execute })?.value, "DeepSeek")
        XCTAssertEqual(rows.first(where: { $0.id == .execute })?.state, .configured)
        XCTAssertEqual(rows.first(where: { $0.id == .reason })?.value, "Not configured")
        XCTAssertEqual(rows.first(where: { $0.id == .orchestrate })?.value, "Not configured")
        XCTAssertEqual(rows.first(where: { $0.id == .vision })?.value, "Not configured")
    }

    func testReasonAssignmentDoesNotPopulateOrchestrateFallbackDisplay() {
        let resolver = SlotStatusResolver { id in id == "anthropic" ? "Anthropic" : id }
        let rows = resolver.rows(slotAssignments: [.reason: "anthropic"])

        XCTAssertEqual(rows.first(where: { $0.id == .reason })?.state, .configured)
        XCTAssertEqual(rows.first(where: { $0.id == .orchestrate })?.state, .notConfigured)
        XCTAssertEqual(rows.first(where: { $0.id == .orchestrate })?.value, "Not configured")
    }

    func testExecuteAssignmentDoesNotPopulateUnassignedSlots() {
        let resolver = SlotStatusResolver { id in id == "deepseek" ? "DeepSeek" : id }
        let rows = resolver.rows(slotAssignments: [.execute: "deepseek"])

        XCTAssertEqual(rows.first(where: { $0.id == .execute })?.state, .configured)
        XCTAssertEqual(rows.first(where: { $0.id == .reason })?.state, .notConfigured)
        XCTAssertEqual(rows.first(where: { $0.id == .orchestrate })?.state, .notConfigured)
        XCTAssertEqual(rows.first(where: { $0.id == .vision })?.state, .notConfigured)
    }

    func testVirtualProviderIDsUseRegistryDisplayName() {
        let resolver = SlotStatusResolver { id in
            if id == "llamacpp:qwen3-coder" {
                return "llama.cpp — qwen3-coder"
            }
            return id
        }
        let rows = resolver.rows(slotAssignments: [.execute: "llamacpp:qwen3-coder"])

        XCTAssertEqual(rows.first(where: { $0.id == .execute })?.value, "llama.cpp — qwen3-coder")
    }

    func testRowsHaveStableAccessibilityIdentifiers() {
        let resolver = SlotStatusResolver { id in id }
        let rows = resolver.rows(slotAssignments: [.execute: "deepseek"])

        XCTAssertEqual(rows.first(where: { $0.id == .execute })?.accessibilityID,
                       AccessibilityID.slotStatusRowPrefix + "execute")
        XCTAssertEqual(rows.first(where: { $0.id == .reason })?.accessibilityID,
                       AccessibilityID.slotStatusRowPrefix + "reason")
        XCTAssertEqual(rows.first(where: { $0.id == .orchestrate })?.accessibilityID,
                       AccessibilityID.slotStatusRowPrefix + "orchestrate")
        XCTAssertEqual(rows.first(where: { $0.id == .vision })?.accessibilityID,
                       AccessibilityID.slotStatusRowPrefix + "vision")
    }
}
