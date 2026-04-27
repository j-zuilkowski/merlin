---
name: debug
description: Structured debugging session - reproduce, isolate, diagnose, fix
user-invocable: true
argument-hint: [error message or test name]
---

Debug $ARGUMENTS using this process:
1. Reproduce - confirm the failure is consistent
2. Isolate - narrow to the smallest failing case
3. Diagnose - identify root cause, not just symptoms
4. Fix - implement the minimal correct change
5. Verify - confirm the fix passes and no regressions introduced
