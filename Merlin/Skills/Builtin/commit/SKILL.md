---
name: commit
description: Generate a commit message from the current staged diff
user-invocable: true
disable-model-invocation: true
allowed-tools: git diff --staged
---

Run `git diff --staged` to get the current staged diff, then write a concise commit message
following this format:
- Subject line: imperative mood, <=72 characters, no trailing period
- Blank line
- Body: 1-3 sentences explaining why if non-obvious
Do not include "Co-authored-by" lines unless I ask.
