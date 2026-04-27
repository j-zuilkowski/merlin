import Foundation

struct TOMLDecoder: Sendable {
    private let jsonDecoder: JSONDecoder

    init() {
        jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601
    }

    func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        let parsed = try TOMLParser.parse(string)
        let foundation = TOMLValue.table(parsed).toFoundation()
        let data = try JSONSerialization.data(withJSONObject: foundation, options: [])
        return try jsonDecoder.decode(T.self, from: data)
    }
}
