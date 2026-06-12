# Task 397b - SPICE optimization implementation

## Traceability

- Plugin spec reference: plugins/electronics/spec.md#research-derived-design-commitments
- Test task: tasks/task-397a-spice-optimization-tests.md

## Behavior

The plugin SHALL use ngspice measurements as authority for simulation-required
designs and SHALL keep optimization bounded to known topologies.

## Implementation

- Add SPICE scenario schema and model resolution policy.
- Run ngspice and parse measurements.
- Add pass/fail measurement envelopes.
- Add supported simulation repair actions.
- Add fixed-topology parameter optimization loops.
- Block unsupported topology changes.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/SPICEOptimizationTests
```

Expected green state: simulation-required designs are evidence-gated and bounded
optimization is verifier-driven.

## Commit

Stage only SPICE/optimization implementation and focused tests.
