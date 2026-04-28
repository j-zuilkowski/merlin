# Phase 61b — Vision Attachment Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 61a complete: failing ContextInjectorVisionTests in place.

Generalize `VisionQueryTool.query` to accept `any LLMProvider` and wire image attachments
through to the vision provider in `ContextInjector`.

---

## Edit: Merlin/Tools/VisionQueryTool.swift

Replace the entire file:

```swift
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
            model: provider.id,
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
```

---

## Edit: Merlin/Engine/ContextInjector.swift

Change the `inlineAttachment` signature and image branch only. Replace the function:

```swift
    static func inlineAttachment(url: URL, visionProvider: (any LLMProvider)? = nil) async throws -> String {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent

        if ext == "pdf" {
            return try inlinePDF(url: url, name: name)
        }

        if sourceExtensions.contains(ext) {
            return try inlineSourceFile(url: url, name: name)
        }

        if imageExtensions.contains(ext) {
            guard let provider = visionProvider,
                  let imageData = try? Data(contentsOf: url),
                  !imageData.isEmpty else {
                return "[Image: \(name) — vision analysis pending]\n"
            }
            let description = (try? await VisionQueryTool.query(
                imageData: imageData,
                prompt: "Describe this image concisely in 1-2 sentences.",
                provider: provider
            )) ?? "vision analysis pending"
            return "[Image: \(name)]\n\(description)\n"
        }

        throw AttachmentError.unsupportedType
    }
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'ContextInjectorVision.*passed|ContextInjectorVision.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `TEST BUILD SUCCEEDED`; all ContextInjectorVisionTests pass.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Tools/VisionQueryTool.swift Merlin/Engine/ContextInjector.swift
git commit -m "Phase 61b — image attachment → vision description; generalize VisionQueryTool"
```
