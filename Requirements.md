# Merlin — Requirements

External dependencies needed to build, run, and fully use Merlin. Merlin itself ships
**no third-party Swift packages** — every dependency below is an external tool, service,
model, or system framework.

Current version: **2.4.0** (build 26). Target platform: **macOS 14+**, Apple Silicon.

---

## 1. Build & Developer Toolchain

Required to build Merlin from source.

| Dependency | Version | Required | Source |
|---|---|---|---|
| macOS | 14.0+ | Yes | https://www.apple.com/macos/ |
| Xcode | 15.4+ | Yes | https://developer.apple.com/xcode/ |
| Swift | 5.10 | Yes | https://www.swift.org/ |
| xcodegen | any recent | Yes | https://github.com/yonaskolb/XcodeGen |
| Code-signing identity ("Merlin Dev Signing") | — | Yes (local builds) | Configured in Xcode → Settings → Accounts: https://developer.apple.com/xcode/ |

CI / sandbox builds bypass signing with `CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`.

---

## 2. LLM Providers — Remote / Cloud

At least one provider (remote **or** local) is required. Remote providers each need an
API key, stored in the macOS Keychain.

| Provider | Endpoint | API key | Source (sign-up / API console) |
|---|---|---|---|
| DeepSeek | `https://api.deepseek.com/v1` | Required | https://platform.deepseek.com/ |
| OpenAI | `https://api.openai.com/v1` | Required | https://platform.openai.com/ |
| Anthropic | `https://api.anthropic.com/v1` | Required | https://console.anthropic.com/ |
| Qwen (Alibaba DashScope) | `https://dashscope.aliyuncs.com/compatible-mode/v1` | Required | https://www.alibabacloud.com/help/en/model-studio/ |
| OpenRouter | `https://openrouter.ai/api/v1` | Required | https://openrouter.ai/ |

---

## 3. Local Model Runners

Optional alternative to cloud providers. No API key; all expose an OpenAI-compatible
`/v1/chat/completions` endpoint.

| Runner | Default endpoint | Source |
|---|---|---|
| llama.cpp router mode | `http://localhost:8081/v1` | https://github.com/ggml-org/llama.cpp |
| LM Studio | `http://localhost:1234/v1` | https://lmstudio.ai/ |
| Ollama | `http://localhost:11434/v1` | https://ollama.com/ |
| Jan.ai | `http://localhost:1337/v1` | https://jan.ai/ |
| LocalAI | `http://localhost:8080/v1` | https://localai.io/ — repo: https://github.com/mudler/LocalAI |
| Mistral.rs | `http://localhost:1234/v1` | https://github.com/EricLBuehler/mistral.rs |
| vLLM-Metal | `http://localhost:8000/v1` | https://docs.vllm.ai/ — repo: https://github.com/vllm-project/vllm |

llama.cpp router mode is the preferred local provider for Merlin. It keeps the
local general model, vision model, and `mmproj` in one router catalog at
`localhost:8081`, supports runtime model load/unload through router endpoints,
and avoids the LM Studio / Mistral.rs `:1234` port collision. LM Studio remains a
reliable first-class alternative with REST model management plus a CLI fallback
at `~/.lmstudio/bin/lms`.

> **Port-collision note.** LM Studio and Mistral.rs share the same default port (`1234`). Only one of the two can run at a time on the defaults; to use both, rebind one of them (`mistralrs --port 1235` and update the matching `baseURL` in Settings → Providers).

---

## 4. Models

Merlin is model-agnostic; these are the known-good choices named in the design docs.
Models are downloaded through the runner or placed in the configured local model
directory (for llama.cpp router mode, usually `~/Models/gguf`), not bundled.

| Use | Model | Source |
|---|---|---|
| Default cloud execute slot | `deepseek-v4-flash` (per `ProviderConfig.swift` default) | https://platform.deepseek.com/ |
| General / execute slot (local) | `qwen/qwen3.6-27b` (or any capable instruct model) | https://huggingface.co/Qwen |
| Vision slot | `Qwen3-VL` GGUF + matching `mmproj` for llama.cpp router mode | https://huggingface.co/Qwen — GGUF quants in the configured local models directory |
| LoRA base model | Local MLX-format instruct model (GGUF cannot be trained by mlx-lm) | User-provided (e.g. https://huggingface.co/models — convert to MLX via `mlx_lm.convert` if downloading HF format) |

---

## 5. LoRA Self-Training Pipeline

Optional — fine-tunes a local MLX-format model on your accepted session data. Apple Silicon only; `mlx_lm.lora` cannot train GGUF or HF-safetensors bases.

| Dependency | Version | Required | Source |
|---|---|---|---|
| Python | 3.9+ | Yes (for LoRA) | https://www.python.org/ |
| mlx_lm (MLX-LM) | any recent | Yes (for LoRA) | https://github.com/ml-explore/mlx-lm — pip: https://pypi.org/project/mlx-lm/ |
| MLX (underlying framework) | bundled with mlx_lm | Yes (for LoRA) | https://github.com/ml-explore/mlx |
| `mlx_lm.server` (adapter inference) | part of mlx_lm | Optional | https://github.com/ml-explore/mlx-lm |
| Base model file | — | Yes (for LoRA) | User-provided MLX-format model |

Adapters are written to `~/.merlin/lora/`.

---

## 6. KiCad / Electronics Domain

Optional — required only for the v2.0 Electronics (PCB/schematic) workflows.

| Dependency | Version | Required for electronics | Source |
|---|---|---|---|
| KiCad | **>= 10.0.0** (lower versions rejected) | Yes | https://www.kicad.org/ |
| Merlin electronics runtime plugin | bundled in `plugins/electronics` | Yes | Built from this repo; the archived `archive/legacy-merlin-kicad-mcp` scaffold is historical reference only |
| FreeRouting | any recent | Yes (auto-routing) | https://github.com/freerouting/freerouting — site: https://www.freerouting.app/ |
| ngspice / SPICE | any recent | Yes (simulation) | https://ngspice.sourceforge.io/ |

---

## 7. Documentation Tools

Optional — used by the v2.2 Project Discipline subsystem (`/project:*` skills). Scanners
degrade gracefully if these are absent.

| Tool | Used for | Source |
|---|---|---|
| Vale | Prose readability grading | https://vale.sh/ — repo: https://github.com/errata-ai/vale |
| DocC | Swift API docs (`xcodebuild docbuild`) | https://www.swift.org/documentation/docc/ |
| rustdoc | Rust API docs (`cargo doc`) | https://doc.rust-lang.org/rustdoc/ |

---

## 8. External Services & Connectors

All optional. Keys/tokens are stored in the Keychain unless noted.

| Service | Purpose | Key/token | Source |
|---|---|---|---|
| xcalibre-server | Book-content RAG + cross-session knowledge graph | `xcalibre_token` in `~/.merlin/config.toml` | Internal — user's own project; no public source. Falls back to a local SQLite KAG store. |
| Brave Search API | `web_search` tool | Keychain (`brave-search`) | https://brave.com/search/api/ |
| GitHub | PR monitoring, issues, file contents, create/merge PR | Keychain (`com.merlin.github`) | https://github.com/ — API: https://docs.github.com/rest |
| Slack | Post channel messages | Keychain (`com.merlin.slack`) | https://api.slack.com/ |
| Linear | Issues, project status, cycle items | Keychain (`com.merlin.linear`) | https://linear.app/ — API: https://developers.linear.app/ |

---

## 9. MCP (Model Context Protocol)

Optional — extends the tool registry with external MCP servers (stdio transport;
configured in `~/.merlin/mcp.json`). Each MCP server the user adds is its own dependency
and may itself require Node/`npx`, Python, or a prebuilt binary.

| Dependency | Source |
|---|---|
| Model Context Protocol (spec & SDKs) | https://modelcontextprotocol.io/ |

---

## 10. System Permissions & Command-Line Tools

### macOS frameworks & permissions

All part of the macOS SDK (installed with Xcode); granted on first use.

| Framework / permission | Needed for | Source |
|---|---|---|
| Accessibility | Reading the live AX element tree for GUI automation | https://developer.apple.com/documentation/accessibility |
| ScreenCaptureKit (Screen Recording) | Screenshot / window capture | https://developer.apple.com/documentation/screencapturekit |
| Speech (Speech Recognition) | Voice dictation (Ctrl+M) | https://developer.apple.com/documentation/speech |
| Core Graphics (CGEvent) | Synthesizing mouse/keyboard input | https://developer.apple.com/documentation/coregraphics |
| AppIntents | Siri / Shortcuts integration | https://developer.apple.com/documentation/appintents |

Merlin is **non-sandboxed** (`com.apple.security.app-sandbox = false`); it also uses the
Keychain and FSEvents, neither of which needs a separate prompt.

### Command-line tools (invoked via subprocess)

| Tool | Required | Used for | Source |
|---|---|---|---|
| git | Yes | Worktree isolation, commit, push, tag | https://git-scm.com/ |
| xcodebuild | Yes (Xcode projects) | Build, test, simulator control | Bundled with Xcode: https://developer.apple.com/xcode/ |
| gh (GitHub CLI) | Optional | Release creation | https://cli.github.com/ |
| python | Only for LoRA | `python -m mlx_lm.lora` | https://www.python.org/ |
| vale | Only for discipline docs | Prose readability | https://vale.sh/ |
| cargo | Only for Rust projects | Build/test (Rust adapter) | https://www.rust-lang.org/ |
| lms (LM Studio CLI) | Optional | Model unload fallback | Bundled with LM Studio: https://lmstudio.ai/ |
| xcodegen | Yes (build) | Regenerate the Xcode project | https://github.com/yonaskolb/XcodeGen |

`xcodegen` is most easily installed via Homebrew (`brew install xcodegen`): https://brew.sh/

---

## Requirements by Feature

| To do this... | You need |
|---|---|
| **Run the agent (software dev)** | macOS 14+, one LLM provider (cloud key **or** a local runner), git |
| **Build Merlin from source** | Xcode 15.4+, Swift 5.10, xcodegen, signing identity |
| **Use cloud models** | An API key for DeepSeek / OpenAI / Anthropic / Qwen / OpenRouter |
| **Use local models** | llama.cpp router mode preferred; LM Studio or Jan.ai are reliable alternatives; skip LocalAI / Ollama / Mistral.rs / vLLM-Metal unless upstream blocker tracking shows a fix |
| **Vision / GUI automation** | A vision model + Accessibility & Screen Recording permissions |
| **Voice dictation** | Speech Recognition permission |
| **LoRA self-training** | Apple Silicon, Python 3.9+, mlx_lm, an MLX-format base model |
| **Electronics / PCB design** | KiCad >= 10.0.0, Merlin `plugins/electronics`, FreeRouting, ngspice |
| **Project Discipline docs** | Vale; DocC (Swift) or rustdoc (Rust) |
| **Web search** | Brave Search API key |
| **Knowledge-graph RAG over books** | xcalibre-server (else local SQLite fallback) |
| **GitHub / Slack / Linear integration** | A token for each, configured in Settings → Connectors |
| **MCP tools** | Whatever each configured MCP server itself requires |
