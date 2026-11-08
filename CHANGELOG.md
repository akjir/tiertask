# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Configurable diagnostic log severity levels (`Debug`, `Info`, `Warning`, `Error`) and independent log storage targets (`Local`, `WebDAV`, `Both`) in Settings (`TEP-002`).
- Dated per-workspace diagnostic log files (`tiertask_<YYYY-MM-DD>_<platform>_<workspaceId>.log`) with `@meta` session headers, 7-day / 5-file local retention pruning, and debounced WebDAV log synchronization.
- Metadata summary card, minimum severity and subsystem tag filters, and manual WebDAV log upload button in the in-app Diagnostic Log viewer.

### Changed

- Standardized diagnostic log entries across all application layers to the structured `<UTC-ISO> [<LEVEL>] [<TAG>] <event> | <key=value ...>` format while preserving logs across clean application exits.

## [0.1.0] - 2026-11-08

### Added

- Initial release of TierTask.
