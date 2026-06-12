import Foundation

let server = WebSearchMCPServer.production()
await server.runStdio()
