# Task 514 - Create v2.4.0 Tag

## Objective

Complete release gate #14 by creating the local `v2.4.0` git tag after gates
#1-#13 passed and Task 513 refreshed the final safety check.

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
