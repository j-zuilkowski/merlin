# Task 383a — Visual accessibility audit tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview
- Prior failure: `VisualLayoutTests/testAccessibilityAudit`

## Behavior

WHEN Merlin launches the fixture workspace THE visible UI SHALL pass the XCTest
accessibility audit without missing labels, low-contrast controls, unknown roles,
or parent/child accessibility mismatches.

GIVEN slot status rows are visible,
WHEN assistive technology focuses a row,
THEN the row SHALL expose a coherent label and value such as
`Execute slot, Not configured`.

GIVEN icon-only toolbar or chat controls are visible,
WHEN assistive technology focuses each control,
THEN each control SHALL expose a meaningful label.

## Red Tests

- Keep `VisualLayoutTests/testAccessibilityAudit` collecting all audit issues.
- Add focused assertions for the highest-signal failures observed in the rerun:
  - slot status rows expose labels and do not appear as unknown-role elements;
  - decorative status indicators are hidden from accessibility or folded into
    their row label;
  - icon-only controls have labels;
  - sidebar/session text contrast is acceptable in the tested appearance mode.
- Do not blanket-ignore accessibility audit categories unless a category is
  documented as an XCTest false positive and covered by a narrower assertion.

## Verification

```bash
xcodegen generate
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests-Live \
  -destination 'platform=macOS' \
  -only-testing:MerlinUITests/VisualLayoutTests/testAccessibilityAudit
```

Expected red state: the audit reports the existing missing-label, contrast,
unknown-role, parent/child, and Touch Bar description issues.
