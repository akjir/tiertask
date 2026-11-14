# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added a subtle task ID header with a copy button at the top of expanded task cards, allowing every task card to expand on tap.
- Added automatic synchronization for external edits to the local TDF file, with a per-workspace toggle in Settings.
- Added in-memory undo via a notification bar action and the Ctrl+Z desktop shortcut for task completion, downgrade, and deletion.
- Added a copy button on the right side of expanded task notes to copy note text to the clipboard.
- Added a delete button with a confirmation dialog in the task editor when editing an existing task.
- Added interactive task status indicator icons for suspension, prerequisite tasks, and activation conditions that open a task information dialog on click or tap.
- Added a POSIX user-space build and installation script for Linux with desktop launcher integration.

### Changed

- Changed WebDAV synchronization to cache server entity tags and modification timestamps, skipping unchanged downloads, parser passes, and redundant uploads while automatically merging concurrent remote edits when a write precondition fails.
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
