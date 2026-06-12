# Task 514 - Create v2.4.0 Tag

## Objective

Complete release gate #14 by creating the local `v2.4.0` git tag after gates
#1-#13 passed and Task 513 refreshed the final safety check.

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#spec-driven-development-methodology

## Behavior

WHEN gates #1-#13 have passed on the current release commit THE system SHALL
create the local `v2.4.0` tag before any branch/tag push.

## Pre-Tag Checks

- Starting commit before this task:
  `8a8f69a Task 513: rerun final release safety check`
- Working tree was clean before editing this task record.
- Local `v2.4.0` tag was absent.
- Remote `refs/tags/v2.4.0` was absent.

## Action

Create the local tag after committing this task record:

```sh
git tag v2.4.0
```

Gate #15, pushing the branch and tag, remains the next release action.
