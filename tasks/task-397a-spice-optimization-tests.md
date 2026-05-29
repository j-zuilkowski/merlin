# Task 397a - SPICE optimization tests

## Traceability

- Plugin spec reference: plugins/electronics/spec.md#research-derived-design-commitments
- Roadmap reference: plugins/electronics/tasks.md#phase-10-simulation-and-optimization

## Behavior

Simulation-required designs SHALL block without simulation evidence, and bounded
optimization SHALL operate only on fixed-topology analog subcircuits.

## Red Tests

- Add SPICE scenario schema tests.
- Add model resolution policy tests.
- Add ngspice measurement parsing tests.
- Add pass/fail envelope tests.
- Add supported simulation repair action tests.
- Add bounded fixed-topology optimization tests.
- Add tests proving optimization cannot invent unsupported topology changes.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/SPICEOptimizationTests
```

Expected red state: tests fail until simulation evidence and optimization loops
exist.

## Commit

Stage only SPICE/optimization tests and fixtures.
