import XCTest
@testable import Merlin

final class ProjectSizeMetricsTests: XCTestCase {

    // MARK: - Default

    func testDefaultReturnsMinimumCeiling() {
        let m = ProjectSizeMetrics.default
        XCTAssertEqual(m.adaptiveCeiling(for: .routine),    10)
        XCTAssertEqual(m.adaptiveCeiling(for: .standard),   10)
        XCTAssertEqual(m.adaptiveCeiling(for: .highStakes), 10)
    }

    // MARK: - Formula: standard tier

    func testSingleFileMeetsMinimum() {
        let m = ProjectSizeMetrics(sourceFileCount: 1)
        // log2(2)*4 = 4 → 10+4=14; standard × 1.0 = 14
        XCTAssertGreaterThanOrEqual(m.adaptiveCeiling(for: .standard), 10)
    }

    func testSmallProject() {
        // 10 files: floor(log2(11))*4 = 3*4=12 → 10+12=22
        let m = ProjectSizeMetrics(sourceFileCount: 10)
        XCTAssertEqual(m.adaptiveCeiling(for: .standard), 22)
    }

    func testMediumProject() {
        // 100 files: floor(log2(101))*4 = 6*4=24 → 10+24=34
        let m = ProjectSizeMetrics(sourceFileCount: 100)
        XCTAssertEqual(m.adaptiveCeiling(for: .standard), 34)
    }

    func testLargeProject() {
        // 5000 files: floor(log2(5001))*4 = 12*4=48 → 10+48=58
        let m = ProjectSizeMetrics(sourceFileCount: 5000)
        XCTAssertEqual(m.adaptiveCeiling(for: .standard), 58)
    }

    func testVeryLargeProjectCapsAt80() {
        // 1_000_000 files would exceed cap
        let m = ProjectSizeMetrics(sourceFileCount: 1_000_000)
        XCTAssertEqual(m.adaptiveCeiling(for: .standard), 80)
    }

    // MARK: - Tier multipliers

    func testRoutineTierIsLowerThanStandard() {
        let m = ProjectSizeMetrics(sourceFileCount: 500)
        let routine  = m.adaptiveCeiling(for: .routine)
        let standard = m.adaptiveCeiling(for: .standard)
        XCTAssertLessThanOrEqual(routine, standard)
    }

    func testHighStakesTierIsHigherThanStandard() {
        let m = ProjectSizeMetrics(sourceFileCount: 100)
        let standard   = m.adaptiveCeiling(for: .standard)
        let highStakes = m.adaptiveCeiling(for: .highStakes)
        XCTAssertGreaterThanOrEqual(highStakes, standard)
    }

    func testRoutineNeverFallsBelowMinimum() {
        // Even with zero files, routine must be ≥ 10
        let m = ProjectSizeMetrics(sourceFileCount: 0)
        XCTAssertGreaterThanOrEqual(m.adaptiveCeiling(for: .routine), 10)
    }

    func testHighStakesNeverExceedsMaximum() {
        let m = ProjectSizeMetrics(sourceFileCount: 999_999)
        XCTAssertLessThanOrEqual(m.adaptiveCeiling(for: .highStakes), 80)
    }

    // MARK: - Monotonicity

    func testCeilingIncreasesWithFileCount() {
        let small  = ProjectSizeMetrics(sourceFileCount: 10).adaptiveCeiling(for: .standard)
        let medium = ProjectSizeMetrics(sourceFileCount: 100).adaptiveCeiling(for: .standard)
        let large  = ProjectSizeMetrics(sourceFileCount: 1000).adaptiveCeiling(for: .standard)
        XCTAssertLessThanOrEqual(small, medium)
        XCTAssertLessThanOrEqual(medium, large)
    }
}
