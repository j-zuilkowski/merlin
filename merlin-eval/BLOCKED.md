# Blocked / Untestable Items

Capabilities that cannot be exercised with what is currently installed or available.
Each entry: what is blocked, why, and what would unblock it.

## Status: none confirmed blocked

The capability probe (2026-05-16) found every scenario area testable:

| Capability | Requirement | Status |
|---|---|---|
| Swift GUI debug | Xcode toolchain | available |
| Rust debug | cargo / rustc 1.94 | available |
| Voice dictation | Speech + microphone | available — pending the `Info.plist` Speech/mic keys (phase 302) |
| xcalibre RAG | xcalibre-server source | available at `localProject/xcalibre-server` |
| LoRA training | Python 3.9.13, mlx_lm, mlx, MLX base model | available |
| Electronics | KiCad 10.0.3, merlin-kicad-mcp, FreeRouting, ngspice | available |

## How to use this file

If, during eval-suite construction or a proving pass, something turns out to be
untestable (a missing tool, an unbuildable dependency, a feature with no reachable
entry point), add an entry here instead of silently skipping it:

```
### <capability>
- Blocked by: <missing tool / broken dependency / unreachable code path>
- Evidence: <command output / file:line>
- Unblock: <what to install or fix>
```
