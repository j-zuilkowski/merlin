# project:revise

Run DisciplineEngine.scan, present findings, and guide the user through resolving them.

## Trigger

User says any of:
- "revise the project"
- "fix discipline drift"
- "show me what needs fixing"
- "run the discipline scanner"
- "/project:revise"
- "what's in pending attention?"

## Steps

1. **Run scan**: Call `DisciplineEngine.scan(projectPath: projectPath)`.
   Display the `ScanReport.findings` grouped by severity: block → nudge → silent.

2. **Present findings** one at a time in order of severity:
   For each finding, display:
   - Severity badge (🔴 block / 🟡 nudge / ⚪ silent)
   - Category and summary
   - Evidence (file path, line number if available)
   - Suggested action

3. **For each finding, prompt for action**:
   - **Accept proposed patch** — apply the suggested fix. For phase-drift findings,
     either update the phase NNb file or create a phase NNc addendum.
   - **Modify** — open the finding in context; user edits; validate and apply.
   - **Dismiss with rationale** — call `DisciplineEngine.dismiss(findingID:rationale:)`.
     Log to `OverrideAuditLog`. Display override count for this category.
   - **Defer** — leave in `pending.json` unchanged.

4. **Batch commit**: After processing a set of accepted findings, produce a single commit
   with a structured message:
   ```
   Revise: fix N discipline findings
   
   - [phaseDrift] ProviderBudget: restore or write addendum
   - [manualCoverageGap] AppSettings.activeProviderID: added manual section
   ```

5. **Summary**: Report accepted / dismissed / deferred counts and remaining queue depth.

## Output

- Modified phase files (addendum phases or updated NNb files).
- New manual sections in doc files.
- Dismissed findings logged to `.merlin/override-log.jsonl`.
- A single git commit per revision batch (never per individual finding).

## Constraints

- Never push — only local commits.
- Never modify an NNb file to remove a surface — create a NNc addendum instead.
- Dismiss rationale is required and logged; dismissal without rationale is not accepted.
- If scan fails (circuit breaker active), report `discipline.disabled` and stop.
