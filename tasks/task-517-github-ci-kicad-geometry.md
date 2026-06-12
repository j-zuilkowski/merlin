# Task 517 - GitHub CI KiCad Geometry

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#spec-driven-development-methodology

## Behavior

WHEN GitHub CI runs without installed KiCad symbol libraries THE system SHALL use bundled generic pin geometry for common KiCad primitive symbols while still rejecting unknown symbols.

## Objective

Repair the GitHub CI failure from PR #3 run `27415472479`, where full unit tests
failed because the macOS runner could not resolve KiCad symbol pin geometry from
installed library roots.

## Evidence

- Failing CI run: `https://github.com/j-zuilkowski/merlin/actions/runs/27415472479`
- Root failures included `PIN_GEOMETRY_UNRESOLVED` for common symbols such as
  `Device:R`, `Device:C`, `Connector:Conn_01x02_Pin`, `Device:D_Bridge_+-AA`,
  `Connector:AudioJack2`, `Device:R_POT`, `Device:Q_NPN_BCE`, and
  `Transistor_FET:Q_NMOS_GDS`.

## Verification

Run the focused materializer and traceability tests locally, then push the
repair and rewatch GitHub CI on PR #3.
