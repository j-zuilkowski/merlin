Status: complete

# Task 459a - Datasheet Cache Settings Tests

Add focused tests proving the electronics plugin owns datasheet PDF cache
configuration and keeps cached PDFs local-first.

Acceptance:
- The plugin settings schema exposes `datasheet_cache_directory` as a path field
  with the default electronics datasheet cache location.
- The plugin settings schema exposes `datasheet_cache_revalidate_after_seconds`
  with a conservative default.
- Runtime component selection honors the plugin settings cache directory when
  the tool payload does not override it.
- Cached datasheet PDFs are reused without network calls while still inside the
  revalidation window.
