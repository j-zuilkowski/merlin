# Developer Guide

This guide covers the mechanics of building, testing, and releasing this project.

<!-- dev-guide:begin:build -->
### Build

```bash
xcodebuild -scheme {scheme} build-for-testing -destination 'platform=macOS' -derivedDataPath /tmp/build CODE_SIGN_IDENTITY=\"\" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```
<!-- dev-guide:end:build -->

<!-- dev-guide:begin:test -->
### Test

```bash
xcodebuild -scheme {scheme} test -destination 'platform=macOS' -derivedDataPath /tmp/build CODE_SIGN_IDENTITY=\"\" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```
<!-- dev-guide:end:test -->

<!-- dev-guide:begin:versioning -->
### Versioning

Version field: `MARKETING_VERSION` in `project.yml`.
<!-- dev-guide:end:versioning -->

<!-- dev-guide:begin:adapter -->
### Adapter

Language: `swift`. API doc generator: `docc`.
Release command: `gh release create v{version} --notes-file RELEASE-v{version}.md --latest`.
<!-- dev-guide:end:adapter -->

### Current Local Provider Defaults

The release-current local-provider inventory includes `llamacpp` (`llama.cpp`) at
`http://localhost:8081/v1` as a first-class router-mode provider.
