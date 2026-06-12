# Task 388a - Dynamic plugin roles tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Plugin spec reference: plugins/electronics/spec.md#dynamic-plugin-roles
- Roadmap reference: plugins/electronics/tasks.md#numbered-tdd-task-map

## Behavior

WHEN a plugin declares model roles THE roles SHALL appear only while that plugin
is loaded.

GIVEN the electronics plugin is loaded,
THEN `electronics.analog_critic` SHALL be available as an optional plugin role.

GIVEN the electronics plugin is unloaded or absent,
THEN `electronics.analog_critic` SHALL not appear in role settings, routing,
calibration/configure targets, status display, or token accounting.

## Red Tests

- Add role registry tests for built-in roles plus plugin-contributed roles.
- Add electronics plugin metadata tests proving `electronics.analog_critic` is
  declared by the plugin, not Merlin core.
- Add unload/absent-plugin tests proving the role disappears.
- Add fallback/required-role tests for optional fallback to `reason` and required
  missing role blocking with `ROLE_UNASSIGNED`.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/DynamicPluginRoleTests \
  -only-testing:MerlinTests/ElectronicsPluginRoleTests
```

Expected red state: tests fail because roles are still fixed core slots.

## Commit

Stage only the new dynamic role tests.
