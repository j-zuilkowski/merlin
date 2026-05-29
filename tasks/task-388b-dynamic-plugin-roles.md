# Task 388b - Dynamic plugin roles implementation

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Plugin spec reference: plugins/electronics/spec.md#dynamic-plugin-roles
- Test task: tasks/task-388a-dynamic-plugin-roles-tests.md

## Behavior

Merlin core SHALL keep built-in roles while allowing loaded plugins to contribute
scoped optional or required roles.

## Implementation

- Add a dynamic role registry that includes built-ins and loaded plugin roles.
- Extend runtime plugin metadata with plugin role declarations.
- Register `electronics.analog_critic` from the electronics plugin.
- Wire dynamic roles into settings, provider routing, calibration/configure,
  status display, and token accounting.
- Implement optional fallback and required-role blocking semantics.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/DynamicPluginRoleTests \
  -only-testing:MerlinTests/ElectronicsPluginRoleTests
```

Expected green state: plugin roles appear and disappear with plugin loading, and
existing fixed-role behavior remains intact.

## Commit

Stage only dynamic-role implementation and focused tests.
