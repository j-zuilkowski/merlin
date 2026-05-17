# S18 — Agent Tool Coverage

Proves **every tool the agent can call actually works** — invoked individually, valid
and invalid paths, result logged. Covers `SURFACE-CENSUS.md` §3.1 (~67 built-in tools +
MCP-registered). This scenario exists because the agent's entire tool surface was absent
from the original eval plan — S1–S6 exercise a subset incidentally; S18 is the
systematic backstop so no tool is "silently dead".

## Mechanism
M1 — drive each tool through the real `ToolRegistry` / `ToolRouter` (the runtime path,
not `ToolDefinitions.all`), with crafted arguments, and assert the result. M3 — a
registry-census assertion: the set of registered tool names equals the expected set, so
a tool dropped from `registerBuiltins()` is caught.

## What is exercised

**Registry census (M3):** after `ToolRegistry.shared.registerBuiltins()`, assert every
expected tool name below is present; assert `tool_discover` returns the full set; assert
no expected tool is missing and no unexpected tool appears.

**Per-tool (M1):** for EACH tool — invoke with valid arguments, assert a sane result;
invoke with invalid/missing arguments, assert a clean structured error (no crash, no
silent empty success). Log the actual arguments, result, and error per tool.

- **File system (7):** `read_file`, `write_file`, `create_file`, `delete_file`,
  `list_directory`, `move_file`, `search_files` — against a scratch fixture dir.
- **Shell (2):** `run_shell`, `bash` — a known command + a failing command (assert exit
  code/stderr surfaced).
- **App control (4):** `app_launch`, `app_list_running`, `app_quit`, `app_focus` —
  against a harmless app (e.g. TextEdit).
- **Discovery (1):** `tool_discover`.
- **Discipline generators (4):** `generate_api_docs`, `generate_dev_guide`,
  `write_vale_styles`, `scaffold_manual_coverage` — against a scratch project; assert
  each produces its artifact. **(No other scenario covers these.)**
- **Xcode (12):** `xcode_build`, `xcode_test`, `xcode_clean`, `xcode_derived_data_clean`,
  `xcode_open_file`, `xcode_xcresult_parse`, `xcode_simulator_list`,
  `xcode_simulator_boot`, `xcode_simulator_screenshot`, `xcode_simulator_install`,
  `xcode_spm_resolve`, `xcode_spm_list` — against the S1 `TaskBoard` fixture.
- **GUI automation (10):** `ui_inspect`, `ui_find_element`, `ui_get_element_value`,
  `ui_click`, `ui_double_click`, `ui_right_click`, `ui_drag`, `ui_type`, `ui_key`,
  `ui_scroll` — against a launched test app.
- **Vision (2):** `ui_screenshot`, `vision_query`.
- **RAG (2):** `rag_search`, `rag_list_books` — overlaps S4; here just confirm the tool
  call returns.
- **Subagent (1):** `spawn_agent` — overlaps S14.
- **Web (1, conditional):** `web_search` — registered only with a key; assert it
  registers when the key is present and is absent otherwise.
- **KiCad / electronics (23):** all `kicad_*` tools — overlaps S6; here confirm each is
  registered and individually invocable.
- **MCP-registered:** with a test MCP server configured, assert its tools register as
  `mcp:<server>:<tool>` and are callable.

## Cross-scenario note
File-system / shell / Xcode tools are exercised in depth by S1; GUI + vision by S1; RAG
by S4; KiCad by S6; subagent by S14; web search by S13. S18 does not replace those — it
**confirms every individual tool** (incl. the ones no capability scenario touches —
`move_file`, `app_quit`, the 4 discipline generators, `xcode_simulator_*`,
`tool_discover`) and runs the registry census.

## Scoring rubric
- [ ] Registry census: every expected tool registered; `tool_discover` returns the full
      set; no tool missing.
- [ ] Each of the ~67 tools: valid-args call returns a sane result.
- [ ] Each tool: invalid-args call fails cleanly (structured error, no crash, no silent
      empty-success).
- [ ] The 4 discipline generators each produce their artifact.
- [ ] `web_search` registers iff a key is present.
- [ ] MCP tools register and are callable.
- [ ] Every tool's arguments + result + error are logged in the result file.

**Score:** tools verified / ~67 + registry-census pass/fail. A registered tool that
errors on a valid call, or is missing from the registry, is a finding.

## Runsheet
1. Phases B–D, 301–306 merged; Merlin built; LM Studio running.
2. Run the S18 harness suite (registry census + per-tool invocation).
3. For tools needing real targets (Xcode → S1 fixture; KiCad → S6 setup; MCP → a test
   server), set those up per the referenced scenario.
4. Score; write `results/S18-<date>.md` with the per-tool argument/result/error log.
5. Any missing, dead, or crash-on-valid-call tool is a finding — top priority (this is
   the exact "silently-dead feature" class the suite exists to catch).
