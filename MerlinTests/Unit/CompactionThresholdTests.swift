import Foundation
import XCTest
@testable import Merlin

@MainActor
final class CompactionThresholdTests: XCTestCase {

    func testThresholdsAreLowered() {
        let cm = ContextManager()
        XCTAssertEqual(cm.preRunCompactionThreshold, 6_000)
        XCTAssertEqual(cm.midLoopCompactionThreshold, 20_000)
    }

    func testPreRunCompactionFiresAt6001Tokens() {
        let cm = ContextManager()
        for index in 0..<7 {
            cm.append(
                Message(
                    role: .tool,
                    content: .text(String(repeating: "x", count: 3_500)),
                    toolCallId: "tc\(index)",
                    timestamp: Date()
                )
            )
        }

        XCTAssertGreaterThan(cm.estimatedTokens, cm.preRunCompactionThreshold)
        cm.compactIfNeededBeforeRun(isContinuation: false)
        XCTAssertEqual(cm.compactionCount, 1)
    }
}
