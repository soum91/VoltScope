# Changelog

This log records verified, release-specific changes. The [Factual release changelog](.github/workflows/release-changelog.yml) GitHub Action adds entries based on the actual commits between published releases. Entries are not fabricated for older versions that have not been audited.

## Unreleased: experimental PowerLog access probe

- Added `VoltScope/PowerLogProbe.m`: a read-only, on-device PowerLog SQLite access attempt for iOS 27 that uses a temporary, recoverable swap of VoltScope's own App Group Caches entry to request a ContainerManager sandbox extension. Database writes are prohibited; an inaccessible file returns a concrete error rather than synthetic app usage.
- Added `VoltScope/PowerLogInspectorView.swift` to Insights: automatic probe on first display, manual Refresh, candidate PowerLog table names and optional raw background-runtime samples, full selectable diagnostic text, clipboard write/read-back verification, native Share and native `.txt` Files export.
- Retained Battery Detective as an optional, collapsed screenshot-OCR comparison and preserved existing charging, widget and BLE features.
- Explicit limitations: signed App Group required, token does not bypass file ownership, database path/schema may differ by iOS build, on-device permission success is not yet verified, and these raw metrics are not per-app measured watts.

