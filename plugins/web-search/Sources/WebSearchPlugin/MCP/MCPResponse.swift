import Foundation

struct MCPResponse {
    static func result(id: JSONValue?, _ result: [String: Any]) -> String {
        var object: [String: Any] = [
            "jsonrpc": "2.0",
            "result": result,
        ]
        object["id"] = id?.foundationValue() ?? NSNull()
        return JSON.objectString(object)
    }

    static func error(id: JSONValue?, code: Int, message: String) -> String {
        var object: [String: Any] = [
            "jsonrpc": "2.0",
            "error": [
                "code": code,
                "message": message,
            ],
        ]
        object["id"] = id?.foundationValue() ?? NSNull()
        return JSON.objectString(object)
    }
}
