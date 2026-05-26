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

## Vision

`project:revise` is also how `vision.md` grows after `project:init` seeds it. On request:
- **Add an idea** — append a new entry to `vision.md`'s `## Active` section.
- **Defer an idea** — move an entry from `## Active` to `## Deferred`, adding a
  "reconsider when" note.
- **Promote an idea** — move an `## Active` entry into `spec.md` as a committed
  design decision; remove it from `vision.md`. From there it follows the pipeline:
  `constitution.md → vision.md → spec.md → tasks/ → code`.
Vision edits are committed in the same batch commit as other revision findings.

1. **Run scan**: Call `DisciplineEngine.scan(projectPath: projectPath)`.
   Display the `ScanReport.findings` grouped by severity: block → nudge → silent.

2. **Present findings** one at a time in order of severity:
   For each finding, display:
   - Severity badge (🔴 block / 🟡 nudge / ⚪ silent)
   - Category and summary
   - Evidence (file path, line number if available)
   - Suggested action

3. **For each finding, prompt for action**:
   - **Accept proposed patch** — apply the suggested fix. For task-drift findings,
     either update the task NNb file or create a task NNc addendum.
   - **Modify** — open the finding in context; user edits; validate and apply.
   - **Dismiss with rationale** — call `DisciplineEngine.dismiss(findingID:rationale:)`.
     Log to `OverrideAuditLog`. Display override count for this category.
   - **Defer** — leave in `pending.json` unchanged.
   - **SDD traceability** — add or repair `## Traceability` and `## Behavior`
     blocks so task docs point at `vision.md` and `spec.md` and contain EARS
     `SHALL` statements.

4. **Batch commit**: After processing a set of accepted findings, produce a single commit
   with a structured message:
   ```
   Revise: fix N discipline findings
   
   - [taskDrift] ProviderBudget: restore or write addendum
   - [manualCoverageGap] AppSettings.activeProviderID: added manual section
   ```

5. **Summary**: Report accepted / dismissed / deferred counts and remaining queue depth.

## Output

- Modified task files (addendum tasks or updated NNb files).
- New manual sections in doc files.
- Dismissed findings logged to `.merlin/override-log.jsonl`.
- A single git commit per revision batch (never per individual finding).

## Constraints

- Never push — only local commits.
- Never modify an NNb file to remove a surface — create a NNc addendum instead.
- Dismiss rationale is required and logged; dismissal without rationale is not accepted.
- If scan fails (circuit breaker active), report `discipline.disabled` and stop.
