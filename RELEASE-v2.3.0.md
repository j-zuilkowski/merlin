# Merlin v2.3.0

## Summary

v2.3.0 makes llama.cpp router mode the first-class local provider path for
Merlin's general and vision workflow, and updates the main workspace provider
status surface to reflect explicit role-slot routing instead of raw provider
inventory.

## What's new

- **First-class llama.cpp provider.** The `llamacpp` provider is validated
  against the OpenAI-compatible endpoint at `http://localhost:8081/v1`.
- **Router-mode local model pairs.** One router-mode `llama-server` can expose
  the configured text model, vision model, and vision `mmproj` behind one
  endpoint.
- **Runtime model management.** `LlamaCppModelManager` adds load/unload support
  through llama-server router endpoints and exposes configured GGUF model IDs.
- **Explicit role-slot routing.** Local model assignments use virtual provider
  IDs such as `llamacpp:<model-id>` so Execute, Reason, Orchestrate, and Vision
  slots can target concrete local models.
- **Workspace slot-status redesign.** The top provider HUD was removed; the
  left-sidebar slot panel now shows effective routing from explicit slot
  assignments only.

## Internal changes

- Added llama.cpp provider/model-manager plumbing for router-mode model
  discovery and lifecycle calls.
- Updated provider configuration and settings UI to treat llama.cpp model IDs as
  concrete role-slot choices.
- Refined slot-status resolution so enabled provider inventory does not imply
  active routing.
- Added release validation coverage for the v2.3.0 app version and provider
  routing behavior.

## Migration

Existing provider settings continue to load. To use the new llama.cpp route,
start the router-mode server on `127.0.0.1:8081`, configure the GGUF text and
vision model IDs in Settings, then assign the desired `llamacpp:<model-id>`
entries to the role slots.
