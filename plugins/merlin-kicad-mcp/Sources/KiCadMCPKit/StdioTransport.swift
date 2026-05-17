import Foundation

/// Reads newline-delimited JSON-RPC messages from stdin, routes each through an
/// `MCPServer`, and writes responses to stdout. Logging goes to stderr only —
/// stdout carries protocol traffic exclusively.
public struct StdioTransport: Sendable {
    let server: MCPServer

    public init(server: MCPServer) {
        self.server = server
    }

    public func run() async {
        let stdin = FileHandle.standardInput
        let stdout = FileHandle.standardOutput
        var buffer = Data()

        while true {
            let chunk = stdin.availableData
            if chunk.isEmpty {
                break   // EOF — the client closed the pipe; exit.
            }
            buffer.append(chunk)

            while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer[buffer.startIndex..<newlineIndex]
                buffer.removeSubrange(buffer.startIndex...newlineIndex)
                guard let line = String(data: lineData, encoding: .utf8) else { continue }
                if let response = await server.handle(line),
                   let out = (response + "\n").data(using: .utf8) {
                    stdout.write(out)
                }
            }
        }
    }
}
