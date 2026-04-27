---
name: refactor
description: Propose a focused refactor for a code section
user-invocable: true
argument-hint: [file or type name]
---

Propose a refactor for $ARGUMENTS. Rules:
- Preserve all existing behaviour (no feature changes)
- Reduce complexity or duplication - do not introduce new abstractions unless clearly warranted
- Explain the motivation for each structural change
- Present a diff or before/after for the key changes
