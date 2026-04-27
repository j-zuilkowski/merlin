import XCTest
@testable import Merlin

final class TOMLDecoderTests: XCTestCase {

    private let decoder = TOMLDecoder()

    // MARK: - Primitive values

    func test_string_basic() throws {
        struct S: Decodable { var name: String }
        let result = try decoder.decode(S.self, from: #"name = "hello""#)
        XCTAssertEqual(result.name, "hello")
    }

    func test_string_literal() throws {
        struct S: Decodable { var path: String }
        let result = try decoder.decode(S.self, from: "path = 'C:\\Users\\no\\escape'")
        XCTAssertEqual(result.path, #"C:\Users\no\escape"#)
    }

    func test_string_multiline_basic() throws {
        struct S: Decodable { var text: String }
        let toml = """
        text = \"\"\"
        line one
        line two\"\"\"
        """
        let result = try decoder.decode(S.self, from: toml)
        XCTAssertEqual(result.text, "line one\nline two")
    }

    func test_string_escape_sequences() throws {
        struct S: Decodable { var v: String }
        let result = try decoder.decode(S.self, from: #"v = "tab:\there""#)
        XCTAssertEqual(result.v, "tab:\there")
    }

    func test_string_unicode_escape() throws {
        struct S: Decodable { var v: String }
        let result = try decoder.decode(S.self, from: #"v = "A""#)
        XCTAssertEqual(result.v, "A")
    }

    func test_integer() throws {
        struct S: Decodable { var count: Int }
        let result = try decoder.decode(S.self, from: "count = 42")
        XCTAssertEqual(result.count, 42)
    }

    func test_integer_negative() throws {
        struct S: Decodable { var n: Int }
        let result = try decoder.decode(S.self, from: "n = -7")
        XCTAssertEqual(result.n, -7)
    }

    func test_integer_underscore() throws {
        struct S: Decodable { var big: Int }
        let result = try decoder.decode(S.self, from: "big = 1_000_000")
        XCTAssertEqual(result.big, 1_000_000)
    }

    func test_integer_hex() throws {
        struct S: Decodable { var v: Int }
        let result = try decoder.decode(S.self, from: "v = 0xFF")
        XCTAssertEqual(result.v, 255)
    }

    func test_float() throws {
        struct S: Decodable { var ratio: Double }
        let result = try decoder.decode(S.self, from: "ratio = 3.14")
        XCTAssertEqual(result.ratio, 3.14, accuracy: 1e-10)
    }

    func test_float_exponent() throws {
        struct S: Decodable { var v: Double }
        let result = try decoder.decode(S.self, from: "v = 6.022e23")
        XCTAssertEqual(result.v, 6.022e23, accuracy: 1e18)
    }

    func test_bool_true() throws {
        struct S: Decodable { var enabled: Bool }
        let result = try decoder.decode(S.self, from: "enabled = true")
        XCTAssertTrue(result.enabled)
    }

    func test_bool_false() throws {
        struct S: Decodable { var debug: Bool }
        let result = try decoder.decode(S.self, from: "debug = false")
        XCTAssertFalse(result.debug)
    }

    func test_comments_ignored() throws {
        struct S: Decodable { var x: Int }
        let result = try decoder.decode(S.self, from: "# comment\nx = 1 # inline")
        XCTAssertEqual(result.x, 1)
    }

    // MARK: - Arrays

    func test_array_of_integers() throws {
        struct S: Decodable { var nums: [Int] }
        let result = try decoder.decode(S.self, from: "nums = [1, 2, 3]")
        XCTAssertEqual(result.nums, [1, 2, 3])
    }

    func test_array_of_strings() throws {
        struct S: Decodable { var tags: [String] }
        let result = try decoder.decode(S.self, from: #"tags = ["a", "b", "c"]"#)
        XCTAssertEqual(result.tags, ["a", "b", "c"])
    }

    func test_array_multiline() throws {
        struct S: Decodable { var items: [Int] }
        let toml = """
        items = [
          1,
          2,
          3,
        ]
        """
        let result = try decoder.decode(S.self, from: toml)
        XCTAssertEqual(result.items, [1, 2, 3])
    }

    // MARK: - Tables

    func test_standard_table() throws {
        struct DB: Decodable { var host: String; var port: Int }
        struct S: Decodable { var database: DB }
        let toml = """
        [database]
        host = "localhost"
        port = 5432
        """
        let result = try decoder.decode(S.self, from: toml)
        XCTAssertEqual(result.database.host, "localhost")
        XCTAssertEqual(result.database.port, 5432)
    }

    func test_dotted_key() throws {
        struct Owner: Decodable { var name: String }
        struct S: Decodable { var owner: Owner }
        let result = try decoder.decode(S.self, from: #"owner.name = "Alice""#)
        XCTAssertEqual(result.owner.name, "Alice")
    }

    func test_inline_table() throws {
        struct Point: Decodable { var x: Int; var y: Int }
        struct S: Decodable { var pos: Point }
        let result = try decoder.decode(S.self, from: "pos = {x = 1, y = 2}")
        XCTAssertEqual(result.pos.x, 1)
        XCTAssertEqual(result.pos.y, 2)
    }

    func test_nested_tables() throws {
        struct Inner: Decodable { var value: String }
        struct Mid: Decodable { var inner: Inner }
        struct S: Decodable { var a: Mid }
        let toml = """
        [a.inner]
        value = "deep"
        """
        let result = try decoder.decode(S.self, from: toml)
        XCTAssertEqual(result.a.inner.value, "deep")
    }

    // MARK: - Array of tables

    func test_array_of_tables() throws {
        struct Product: Decodable { var name: String; var sku: Int }
        struct S: Decodable { var products: [Product] }
        let toml = """
        [[products]]
        name = "Hammer"
        sku = 738594937

        [[products]]
        name = "Nail"
        sku = 284758393
        """
        let result = try decoder.decode(S.self, from: toml)
        XCTAssertEqual(result.products.count, 2)
        XCTAssertEqual(result.products[0].name, "Hammer")
        XCTAssertEqual(result.products[1].sku, 284758393)
    }

    func test_array_of_tables_nested() throws {
        struct Fruit: Decodable {
            struct Variety: Decodable { var name: String }
            var name: String
            var varieties: [Variety]
        }
        struct S: Decodable { var fruits: [Fruit] }
        let toml = """
        [[fruits]]
        name = "apple"

          [[fruits.varieties]]
          name = "red delicious"

          [[fruits.varieties]]
          name = "granny smith"

        [[fruits]]
        name = "banana"

          [[fruits.varieties]]
          name = "plantain"
        """
        let result = try decoder.decode(S.self, from: toml)
        XCTAssertEqual(result.fruits.count, 2)
        XCTAssertEqual(result.fruits[0].varieties.count, 2)
        XCTAssertEqual(result.fruits[0].varieties[1].name, "granny smith")
        XCTAssertEqual(result.fruits[1].varieties[0].name, "plantain")
    }

    // MARK: - Optional fields

    func test_optional_missing_key_is_nil() throws {
        struct S: Decodable { var x: Int; var y: Int? }
        let result = try decoder.decode(S.self, from: "x = 1")
        XCTAssertEqual(result.x, 1)
        XCTAssertNil(result.y)
    }

    // MARK: - Error cases

    func test_duplicate_key_throws() throws {
        struct S: Decodable { var x: Int }
        XCTAssertThrowsError(try decoder.decode(S.self, from: "x = 1\nx = 2"))
    }

    func test_invalid_value_throws() throws {
        struct S: Decodable { var x: Int }
        XCTAssertThrowsError(try decoder.decode(S.self, from: "x = @bad"))
    }

    func test_unterminated_string_throws() throws {
        struct S: Decodable { var x: String }
        XCTAssertThrowsError(try decoder.decode(S.self, from: #"x = "unterminated"#))
    }

    // MARK: - Round-trip with real config shape

    func test_merlin_config_shape() throws {
        struct Hook: Decodable { var event: String; var command: String }
        struct Provider: Decodable { var name: String; var base_url: String? }
        struct Config: Decodable {
            var auto_compact: Bool
            var hooks: [Hook]
            var providers: [Provider]
        }
        let toml = """
        auto_compact = true

        [[hooks]]
        event = "PreToolUse"
        command = "echo pre"

        [[hooks]]
        event = "Stop"
        command = "echo stop"

        [[providers]]
        name = "anthropic"

        [[providers]]
        name = "lmstudio"
        base_url = "http://localhost:1234"
        """
        let result = try decoder.decode(Config.self, from: toml)
        XCTAssertTrue(result.auto_compact)
        XCTAssertEqual(result.hooks.count, 2)
        XCTAssertEqual(result.hooks[0].event, "PreToolUse")
        XCTAssertEqual(result.providers[1].base_url, "http://localhost:1234")
    }
}
