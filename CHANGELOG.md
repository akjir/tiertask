# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added TierTask Data Format (TDF) 0.8.0 as the standalone storage format with byte-exact canonical serialization.
- Added local schedule anchors on recurring deadlines to preserve month-end dates and local clock times across shorter months and daylight-saving transitions, shown in the task information dialog when clamped or shifted.
- Added cooperative host-local file locking outside synced folders and conditional initial-creation guards on WebDAV uploads to prevent concurrent local or remote overwrites.
- Added localized synchronization status banners for deletion conflicts, recovery prompts, and version history rollbacks.
- Added per-file readability status diagnostics showing whether local, remote, or both files failed or remain intact.

### Changed

- Changed deadline and deferral editing in the task editor to use the workspace local time zone consistently across cards, info dialogs, and forms.
- Changed multi-stage local and WebDAV synchronization to defer automatic deferral and dependency cleanup until the authoritative final sync stage.

### Removed

- Removed automatic loading and conversion support for pre-0.8.0 TDF files (versions 0.2.0 through 0.7.0).

### Fixed

- Fixed automatic system time-zone mode to apply historical and future daylight-saving transitions when evaluating conditions and advancing recurring tasks.

## [0.3.0] - 2026-11-16

### Added

- Added an interactive task history journal in the task information dialog and task editor, with card history indicators.
- Added multi-line deferral and deadline notes and recurring preparation lead days in the task editor and task information dialog.
- Added a per-workspace deadline lead window setting in Settings to choose when upcoming deadlines automatically advance tasks toward Focus.
- Added a deadline auto-prioritization toggle in the task editor, urgency badges for upcoming and overdue deadlines, and live schedule updates.
- Added a label details dialog in the top bar, drawer, and task cards to view notes, open links, inspect conditions, and edit labels.
- Added reference link management with inline editing and reordering in the label editor.
- Added support for TierTask Data Format (TDF) 0.7.0 with automatic migration from version 0.6.0.
- Added TDF 0.7.0 support for label reference links, deferral and deadline notes, recurring preparation lead days, and task history logs.
- Added a copyable task ID header on expanded task cards and enabled expanding every task card on tap.
- Added automatic synchronization for external edits to the local TDF file, with a per-workspace toggle in Settings.
- Added undo via the notification bar and Ctrl+Z shortcut for task completion, downgrade, and deletion.
- Added a copy button on expanded task notes to copy note text to the clipboard.
- Added a delete button with a confirmation dialog in the task editor when editing an existing task.
- Added interactive status indicator icons on task cards that open the task information dialog for deferrals, prerequisites, and conditions.
- Added a user-space Linux build and installation script with desktop launcher integration.

### Changed

- Changed queued tasks with deadlines inside the lead window (24 hours by default) to advance toward Focus automatically, re-enabling auto-prioritization when promoted to Priority.
- Changed synchronization and task updates to automatically clear expired suspension locks and completed one-time task dependencies.
- Changed WebDAV synchronization to skip unchanged transfers and automatically merge concurrent remote edits on save.
- Changed task cards to collapse more than three status indicator icons into a single summary indicator icon.
- Changed task creation to pre-select the currently active label filter.

## [0.2.0] - 2026-11-09

### Added

- Added configurable diagnostic log severity levels and independent local or WebDAV log storage targets in Settings.
- Added dated per-workspace diagnostic log files with automatic local retention pruning and WebDAV synchronization.
- Added a metadata summary, severity and subsystem filters, and manual WebDAV upload in the diagnostic log viewer.
- Added colored label indicator blocks with hover tooltips along the bottom edge of task cards.
- Added a color wheel picker dialog in the label editor.
- Added explanatory hover tooltips to attribute chips in the task editor.
- Added support for TierTask Data Format (TDF) 0.6.0 with automatic migration from version 0.5.1.
- Added reusable locations management, scoped label queues with drawer indicators, and informational due dates on tasks.
- Added selectable location coordinate resolution from GPS coordinates, street addresses, and Google Plus Codes.

### Changed

- Changed diagnostic logging to use a structured format and preserve log files across clean application exits.

## [0.1.0] - 2026-11-08

### Added

- Initial release of TierTask.
