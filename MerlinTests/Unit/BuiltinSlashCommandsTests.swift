import XCTest
@testable import Merlin

/// Pins the built-in slash command list surfaced by the SkillsPicker. These
/// are the four commands handled by `SlashCommandHandler` + the inline
/// `/rewind` and `/btw` branches in `ChatView` — they need to be visible to
/// the user in the autocomplete picker, not just discoverable via memory.
final class BuiltinSlashCommandsTests: XCTestCase {

    func testFourBuiltinsRegistered() {
        let names = Set(BuiltinSlashCommands.all.map(\.name))
        XCTAssertEqual(names, Set(["calibrate", "compact", "rewind", "btw"]),
                       "If new built-in commands are added or removed, update both this test and SkillsPicker's rendering.")
    }

    func testEveryBuiltinHasNonEmptyDescription() {
        for cmd in BuiltinSlashCommands.all {
            XCTAssertFalse(cmd.description.isEmpty,
                           "Built-in /\(cmd.name) is missing a description — needed for picker UX")
        }
    }

    func testStableOrdering() {
        // Order shown in the picker is part of the contract — calibrate first
        // (most-used in current workflows), then the others alphabetically.
        let expectedOrder = ["calibrate", "btw", "compact", "rewind"]
        XCTAssertEqual(BuiltinSlashCommands.all.map(\.name), expectedOrder)
    }

    // MARK: - Query matching

    func testEmptyQueryReturnsAll() {
        let matched = BuiltinSlashCommands.matching(query: "")
        XCTAssertEqual(matched.count, BuiltinSlashCommands.all.count)
    }

    func testQueryMatchesPrefixCaseInsensitive() {
        let matched = BuiltinSlashCommands.matching(query: "CAL")
        XCTAssertEqual(matched.map(\.name), ["calibrate"])
    }

    func testQueryMatchesDescriptionSubstring() {
        // `/btw` description includes "side question"; match by content.
        let matched = BuiltinSlashCommands.matching(query: "side")
        XCTAssertTrue(matched.contains { $0.name == "btw" },
                      "Description search must match /btw on 'side'")
    }

    func testQueryNoMatchReturnsEmpty() {
        let matched = BuiltinSlashCommands.matching(query: "nonexistent")
        XCTAssertTrue(matched.isEmpty)
    }
}
