import Foundation

struct VisionResponse: Codable, Sendable {
    var x: Int?
    var y: Int?
    var action: String?
    var confidence: Double?
    var description: String?
}

enum VisionQueryTool {
    static func query(imageData: Data, prompt: String, provider: any LLMProvider) async throws -> String {
        let encodedImage = imageData.base64EncodedString()
        let request = CompletionRequest(
            model: provider.resolvedModelID,
            messages: [
                Message(
                    role: .user,
                    content: .parts([
                        .imageURL("data:image/jpeg;base64,\(encodedImage)"),
                        .text(prompt)
                    ]),
                    timestamp: Date()
                )
            ],
            stream: true,
            maxTokens: 256,
            temperature: 0.1
        )

        let stream = try await provider.complete(request: request)
        var response = ""
        for try await chunk in stream {
            if let content = chunk.delta?.content {
                response += content
            }
        }
        return response
    }

    static func parseResponse(_ raw: String) -> VisionResponse? {
        let decoder = JSONDecoder()
        if let data = raw.data(using: .utf8),
           let decoded = try? decoder.decode(VisionResponse.self, from: data) {
            return decoded
        }

        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}") else {
            return nil
        }

        let json = String(raw[start...end])
        guard let data = json.data(using: .utf8) else {
            return nil
        }

        return try? decoder.decode(VisionResponse.self, from: data)
    }
}
