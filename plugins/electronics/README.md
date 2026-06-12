# Electronics Plugin

`plugins/electronics` is the canonical first-party Tier-1 electronics plugin.
It registers KiCad, FreeRouting, workflow, verification, settings, progress, and
artifact capabilities through Merlin's workspace message bus.

The forward design direction is captured in
`plugins/electronics/docs/research-design-overview.md`: research-derived staged
electronics synthesis, KiCad-backed artifact authority, generic evidence gates,
and no hard-coded project generators.

The plugin-owned product specification is `plugins/electronics/spec.md`.
The scoped implementation task list is `plugins/electronics/tasks.md`.

Current status: the electronics domain is finished as evidence-gated workflow
infrastructure. The full GUI proof reads the active project spec, generates
DesignIntent and Circuit IR, then stops at
`COMPONENT_SELECTION_REVISION_BLOCKED` when concrete component/catalog evidence
is missing. That status is intentionally not a `FAB_READY` claim.

The older `archive/legacy-merlin-kicad-mcp` directory is a legacy
out-of-process transport scaffold kept only for historical reference.
