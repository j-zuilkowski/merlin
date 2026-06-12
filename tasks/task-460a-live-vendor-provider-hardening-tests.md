Status: complete

# Task 460a - Live Vendor Provider Hardening Tests

Add focused tests proving live catalog provider discovery remains bounded and
local-first.

Acceptance:
- Cached live catalog evidence can select a component even when the uncached
  live query budget is zero.
- A zero live query budget blocks before credential lookup or network provider
  construction.
- Explicit KiCad roots keep the tests from depending on host library discovery.
