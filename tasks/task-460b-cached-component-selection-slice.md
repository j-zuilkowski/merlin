Status: complete

# Task 460b - Cached Component Selection Slice

Verify a small component-selection path that uses cached or local provider
evidence before any full AmpDemo run.

Acceptance:
- The slice exercises live catalog cache reuse without credentials.
- The slice exercises provider terms gating without producing missing credential
  noise.
- The slice keeps live vendor providers disabled or budgeted unless cached
  evidence is already present.
