# Changelog

## [v1.1.17] - 2026-11-11

## Verified changes since v1.1.14

- build: remove unavailable iOS xpc linker library ([`7f77ad6d`](https://github.com/soum91/VoltScope/commit/7f77ad6d3b029f1f51bece4aabd6a28cbe808894); `project.yml`)
- fix: use ARC-compatible XPC identifier lifetime in PowerLog probe ([`62706458`](https://github.com/soum91/VoltScope/commit/627064589ec106217ba6a1e090c39ff09b313a96); `VoltScope/PowerLogProbe.m`)
- feat: add on-device PowerLog access probe and diagnostic export ([`cf322363`](https://github.com/soum91/VoltScope/commit/cf322363ff88457f5d5faa033593b7023e3f94bc); `.github/workflows/build.yml`, `README.md`, `THIRD_PARTY_NOTICES.md`, and 6 more)

[Inspect exact code changes](https://github.com/soum91/VoltScope/compare/v1.1.14...v1.1.17)

This log records verified, release-specific changes. The [Factual release changelog](.github/workflows/release-changelog.yml) GitHub Action adds entries based on the actual commits between published releases. Entries are not fabricated for older versions that have not been audited.

## Unreleased: experimental PowerLog access probe

- Added `VoltScope/PowerLogProbe.m`: a read-only, on-device PowerLog SQLite access attempt for iOS 27 that uses a temporary, recoverable swap of VoltScope's own App Group Caches entry to request a ContainerManager sandbox extension. Database writes are prohibited; an inaccessible file returns a concrete error rather than synthetic app usage.
- Added `VoltScope/PowerLogInspectorView.swift` to Insights: automatic probe on first display, manual Refresh, candidate PowerLog table names and optional raw background-runtime samples, full selectable diagnostic text, clipboard write/read-back verification, native Share and native `.txt` Files export.
- Retained Battery Detective as an optional, collapsed screenshot-OCR comparison and preserved existing charging, widget and BLE features.
- Explicit limitations: signed App Group required, token does not bypass file ownership, database path/schema may differ by iOS build, on-device permission success is not yet verified, and these raw metrics are not per-app measured watts.

