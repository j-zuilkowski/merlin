import XCTest
@testable import Merlin

final class SessionSidebarHelpersTests: XCTestCase {

    // MARK: - RelativeTimestampFormatter

    func test_now_returns_now_string() {
        let result = RelativeTimestampFormatter.string(from: Date(), now: Date())
        XCTAssertEqual(result, "now")
    }

    func test_30_seconds_ago_returns_now() {
        let date = Date().addingTimeInterval(-30)
        let result = RelativeTimestampFormatter.string(from: date, now: Date())
        XCTAssertEqual(result, "now")
    }

    func test_90_seconds_ago_returns_minutes() {
        let date = Date().addingTimeInterval(-90)
        let result = RelativeTimestampFormatter.string(from: date, now: Date())
        XCTAssertEqual(result, "1m")
    }

    func test_45_minutes_ago_returns_minutes() {
        let now = Date()
        let date = now.addingTimeInterval(-45 * 60)
        let result = RelativeTimestampFormatter.string(from: date, now: now)
        XCTAssertEqual(result, "45m")
    }

    func test_2_hours_ago_returns_hours() {
        let now = Date()
        let date = now.addingTimeInterval(-2 * 3600)
        let result = RelativeTimestampFormatter.string(from: date, now: now)
        XCTAssertEqual(result, "2h")
    }

    func test_23_hours_ago_returns_hours() {
        let now = Date()
        let date = now.addingTimeInterval(-23 * 3600)
        let result = RelativeTimestampFormatter.string(from: date, now: now)
        XCTAssertEqual(result, "23h")
    }

    func test_1_day_ago_returns_days() {
        let now = Date()
        let date = now.addingTimeInterval(-86400)
        let result = RelativeTimestampFormatter.string(from: date, now: now)
        XCTAssertEqual(result, "1d")
    }

    func test_5_days_ago_returns_days() {
        let now = Date()
        let date = now.addingTimeInterval(-5 * 86400)
        let result = RelativeTimestampFormatter.string(from: date, now: now)
        XCTAssertEqual(result, "5d")
    }

    func test_1_week_ago_returns_weeks() {
        let now = Date()
        let date = now.addingTimeInterval(-7 * 86400)
        let result = RelativeTimestampFormatter.string(from: date, now: now)
        XCTAssertEqual(result, "1w")
    }

    func test_10_weeks_ago_returns_weeks() {
        let now = Date()
        let date = now.addingTimeInterval(-70 * 86400)
        let result = RelativeTimestampFormatter.string(from: date, now: now)
        XCTAssertEqual(result, "10w")
    }

    func test_future_date_returns_now() {
        let date = Date().addingTimeInterval(60)
        let result = RelativeTimestampFormatter.string(from: date, now: Date())
        XCTAssertEqual(result, "now")
    }
}
