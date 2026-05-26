# Electronics Plugin

`plugins/electronics` is the canonical first-party Tier-1 electronics plugin.
It registers KiCad, FreeRouting, workflow, verification, settings, progress, and
artifact capabilities through Merlin's workspace message bus.

The older `plugins/merlin-kicad-mcp` directory is a legacy out-of-process
transport scaffold and is no longer the architecture source of truth.
