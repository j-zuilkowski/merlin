Status: complete

# Task 459b - Datasheet Cache Settings

Implement plugin-owned datasheet PDF cache settings and keep datasheet storage
local-first.

Acceptance:
- `datasheet_cache_directory` appears only in the electronics plugin settings
  schema and defaults to `~/Library/Application Support/Merlin/plugins/electronics/datasheets`.
- `datasheet_cache_revalidate_after_seconds` appears only in the electronics
  plugin settings schema and defaults to seven days.
- The provider settings UI displays and persists the datasheet cache directory
  and revalidation interval under electronics settings.
- Runtime component selection resolves the cache directory from payload,
  provider config, plugin settings, then the default path.
- Existing local datasheet PDFs are used before any new download unless the
  revalidation interval has elapsed.
