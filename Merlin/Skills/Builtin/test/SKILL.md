---
name: test
description: Write tests for a function, type, or module
user-invocable: true
argument-hint: [function or module name]
---

Write thorough unit tests for $ARGUMENTS following the project's TDD conventions:
- Use XCTest
- Cover happy path, edge cases, and error paths
- No mocks unless the dependency is external I/O
- Tests must compile and fail before the implementation exists
