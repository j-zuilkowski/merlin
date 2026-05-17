# merlin-kicad-mcp

The MCP server for Merlin's KiCad electronics domain. A standalone macOS command-line
process that speaks JSON-RPC 2.0 over stdio and exposes the `kicad_*` tool family
(version gate, schematic ingestion, component/library prep, project compile, board
setup, placement/routing, ERC/DRC, simulation, fabrication export) to Merlin's
`MCPBridge`.

Merlin ships the client side (`Merlin/Electronics/`); this package is the server it
connects to.

## Build

```bash
swift build -c release
```

## Test

```bash
swift test
```

## Run

`./run` launches the server (building the release binary on first use). Wire it into a
project's `.mcp.json`:

```json
{ "mcpServers": { "kicad": { "command": "/abs/path/to/merlin-kicad-mcp/run", "transport": "stdio" } } }
```

## Layout

- `Sources/KiCadMCPKit/` — protocol core (`MCPServer`, `StdioTransport`), tool registry,
  the `kicad_*` tool surface (`KiCadTools`), `kicad-cli` wrapper, project materializer.
- `Sources/merlin-kicad-mcp/` — thin executable entry point.
- `phases/ROADMAP.md` — the TDD phase decomposition.

`kicad-cli` is expected inside the KiCad 10 app bundle at
`/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli`.
