# merlin-kicad-mcp — Phase Roadmap

The decomposition of the `merlin-kicad-mcp` server into TDD phases. Each numbered
feature phase is a `NNa` (failing tests) + `NNb` (implementation) pair, except phase 00
(scaffold) and phase 15 (release), which are single phases.

Build order is dependency-ordered: protocol/transport → tool plumbing → KiCad access →
the tool families → integration. Do not start a phase until the previous one is
committed.

The tool contract is pinned by Merlin's existing client — `architecture.md` §2241–2263
in `~/Documents/localProject/merlin/` tables all ~23 tools with their inputs/outputs,
and `Merlin/Electronics/KiCadToolDefinitions.swift` confirms the names.

---

## Phases

| Phase | Name | Scope |
|---|---|---|
| 00 | Scaffold | `Package.swift` (executable `merlin-kicad-mcp` + library `KiCadMCPKit` + test target), `.gitignore`, `README.md`, first commit into the Merlin repo. |
| 01 | MCP server core | JSON-RPC 2.0 message types; newline-delimited stdio transport; MCP lifecycle — `initialize` handshake, `tools/list`, `tools/call`, `resources/list`, `resources/read`; structured error envelope. |
| 02 | Tool registry + dispatch | A `Tool` abstraction (name, OpenAI-format JSON schema, async handler); a registry; routing `tools/call` to handlers; tool-not-found and bad-arguments errors. |
| 03 | DomainManifest resource | Serve `merlin://domain/manifest` returning a `DomainManifest` JSON that decodes into Merlin's `DomainManifest` type — id `kicad`, taskTypes, highStakesKeywords, systemPromptAddendum, verificationCommands. |
| 04 | kicad-cli wrapper + version gate | Locate `kicad-cli` (app-bundle path); subprocess runner; `kicad_check_version` (parse major, gate ≥ 10 → `BLOCKED_VERSION`); `kicad_cli_path` resolution. |
| 05 | Canonical schemas | The 9 canonical `Codable` schemas — `ExtractionReport`, `DesignIntent`, component matrix, `NetClassPlan`, board profile, placement plan, route report, verification reports, fab outputs. |
| 06 | S-expression parser/writer | `.kicad_sch` / `.kicad_pcb` S-expression read/write with round-trip tests. |
| 07 | Schematic ingestion tools | `kicad_ingest_schematic`, `kicad_answer_clarification`, `kicad_build_intent_model`. |
| 08 | Component & library tools | `kicad_select_components`, `kicad_prepare_libraries`, `kicad_assign_footprints`. |
| 09 | Project compile + board setup | `kicad_compile_project`, `kicad_apply_board_profile`, `kicad_generate_net_classes`. |
| 10 | Placement + routing | `kicad_place_components`, `kicad_route_pass` (FreeRouting HTTP API via DSN/SES interchange), `kicad_check_connectivity`. |
| 11 | Electrical verification gates | `kicad_run_erc`, `kicad_run_drc`, `kicad_check_parity`. |
| 12 | Simulation | `kicad_run_spice`, `kicad_evaluate_simulation`. |
| 13 | Visual inspection | `kicad_visual_inspect` — screenshot evidence, overlap/orientation/readability findings. |
| 14 | Fabrication + vendor | `kicad_export_fab`, `kicad_prepare_vendor_order`, `kicad_submit_vendor_order`, `kicad_package_release`. |
| 15 | Integration + release | End-to-end test against Merlin's `MCPDomainAdapter` handshake; document wiring into `~/.merlin/mcp.json`; tag `v0.1.0`. |

---

## Notes

- **Phases 01–04 are the foundation** — protocol, plumbing, KiCad access. Nothing in
  07–14 can be verified end-to-end until 04 lands.
- **Phases 07–14 each depend on 05 (schemas) and 06 (S-expr parser).**
- **FreeRouting** (phase 10) needs an API key; the phase will read it from an env var /
  config, never hardcode it.
- The tool families in 07–14 may each split into more than one `NN`/`NN+1` pair if a
  phase's test surface grows too large — keep each phase to one coherent, verifiable
  unit of work.
- Estimated total: ~30 phase files (00 + 01–14 paired + 15).
