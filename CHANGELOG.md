# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Configurable diagnostic log severity levels (`Debug`, `Info`, `Warning`, `Error`) and independent log storage targets (`Local`, `WebDAV`, `Both`) in Settings (`TEP-002`).
- Dated per-workspace diagnostic log files (`tiertask_<YYYY-MM-DD>_<platform>_<workspaceId>.log`) with `@meta` session headers, 7-day / 5-file local retention pruning, and debounced WebDAV log synchronization.
- Metadata summary card, minimum severity and subsystem tag filters, and manual WebDAV log upload button in the in-app Diagnostic Log viewer.
- Added colored label indicator blocks with hover tooltips along the bottom edge of task cards.
- Added a custom color wheel picker dialog next to the color field in the label editor.
- Added hover tooltips to the `Priority`, `Someday`, `Suspended`, `Repeat`, `Auto-finish`, `Any day`, `Any time`, and `Any location` chips in the task editor explaining their behavior.
- Defined the normative TierTask Data Format (`TDF`) `0.6.0` specification in `spec/TDF_SPEC_0.6.0.md` and added the machine-readable conformance fixture suite in `spec/conformance/v0.6.0/` (`TEP-003`).
- Implemented the TierTask Data Format (`TDF`) `0.6.0` runtime, reusable locations management in the navigation drawer, `scoped` label queue partitioning, informational `due` dates on tasks, and `0.5.1 -> 0.6.0` document migration (`TEP-004`).
- Added a scoped indicator icon next to the task count for scoped labels in the navigation drawer.
- Added selectable location source resolution (`GPS Coordinates`, `Address`, and `Google Plus Code`) with offline Plus Code decoding and multi-match address selection in the location editor (`TEP-005`).

### Changed

- Standardized diagnostic log entries across all application layers to the structured `<UTC-ISO> [<LEVEL>] [<TAG>] <event> | <key=value ...>` format while preserving logs across clean application exits.

## [0.1.0] - 2026-11-08

### Added

- Initial release of TierTask.
