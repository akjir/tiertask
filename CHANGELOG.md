# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added Linux, Android, and Windows support for the 6-tier task board (`Focus`, `Ready`, `Planned`, `Blocked`, `Someday`, `Completed`).
- Added English (`en`, default) and German (`de`) localization with `System`, `English`, and `Deutsch` language selection in Settings.
- Added theme mode selection (`System`, `Light`, `Dark`) and runtime Material 3 color palette switching (`Slate` and `Navy`) in Settings.
- Added the `TierTask` application logo across Linux, Android, and Windows launcher icons and the navigation drawer header.
- Added single-pass $O(N)$ TierTask Data Format (`tdf 0.5.0`) scanning, parsing, and canonical `LF` serialization with 10-character Base62 entity identifiers (`<6xBase62Random><4xBase62Time>`), shared `queue` and `deleted` (`generation`) root blocks, and explicit `0.2.0 -> 0.3.0 -> 0.4.0 -> 0.5.0` version migration.
- Added dynamic 6-tier evaluation with `Focus` (`3`) and `Ready` (`5`) soft WIP limits, `subtasks auto-finish` checklist completion, and 30-day UTC pruning for completed tasks and `deleted` tombstones.
- Added configurable storage modes (`Local`, `WebDAV`, `Both`), local `.tdf` file persistence, and two-stage three-way synchronization (`In-Memory <-> Local File <-> WebDAV`) using baseline comparison and monotonic UTC `modified` timestamps.
- Added multi-workspace management in the navigation drawer to switch, create, rename, and delete isolated `.tdf` workspaces without restarting the application.
- Added a desktop `Change Directory` action in Settings on Linux and Windows to move the local `.tdf` file via a native folder picker without overwriting existing targets.
- Added `Wipe Local TDF File` and `Wipe Remote TDF File` actions in Settings with filename confirmation, sync baseline reset, and optional `.bak` / `.bak.001`+ backup creation.
- Added a `Time Zone` setting (`Automatic` or `Manual` UTC offset) so recurring schedules and wall-clock conditions evaluate in local time while point-in-time directives persist in UTC.
- Added foreground-only location determination (`Off` / `On`, default `Off`) across Android, Linux, and Windows with a 3-state top-bar status indicator, location details popup, and live `condition location` evaluation.
- Added an opt-in diagnostic logging system (`Enable Diagnostic Log`, default `Off`) with credential redaction, a 5,000-line rolling `tiertask.log` ring buffer, crash log preservation across unclean exits, and an in-app `Diagnostic Log` viewer.
- Added a bottom-anchored SemVer 2.0.0 version and Git build metadata footer (`Version 0.1.0+<count>.<hash>[.dev]`) in the navigation drawer.
- Added horizontal 6-tier `PageView` navigation with a bottom `TierPageIndicator` supporting desktop hover previews, Left/Right arrow keys, and hold-and-drag wave selection.
- Added an inline bottom quick-add bar (`Priority`, `Someday`, upward-floating `Labels` menu, `Advanced`, and `Cancel`) that stacks automatically on narrow viewports.
- Added a full-screen task editor supporting notes, scheduling (`Priority`, `Someday`, `Suspended` with `forever` or date/time pickers), completion-relative recurrence (`repeat <count> <days|weeks|months> [<HH:MM[:SS]>]`), labels, subtasks (`auto-finish`), repeatable clickable links (`link "<title>" "<uri>"`), searchable prerequisite dependencies (`blocked <task-id>[:<required-completion>]` with cycle detection), and activation conditions (`day`, `time`, `location`, and `any` resets).
- Added a dedicated label management screen and full label editor (`name`, `#RRGGBB` `color` presets and hex input, `note`, and inherited `day`, `time`, and `location` conditions) alongside alphabetical label filtering with open task count badges in the navigation drawer.
- Added passive right-side task pill indicators (`priority`, `repeat`, `note`, `links`, and `subtasks` with hover tooltips), expandable task details drawers (notes, clickable links, and interactive subtask steps), right-chevron `>` tier downgrading, completed task restoration, and directional task transition animations.
- Added an inline focus-aware clear button (`X`) across all text input fields in Settings, the task and label editors, and the quick-add bar.

### Changed

- Changed `.tdf` tier derivation, task downgrade, recurring task rescheduling, and synchronization to `TDF_SPEC.md` Version `0.5.0`, slicing `Focus`, `Ready`, and `Planned` in `queue` block order and repositioning downgraded tasks inside `queue` without mutating `queued` timestamps.
- Changed task completion and restoration so completing a task marks and locks all of its subtasks as completed (`step true`), while restoring a completed task unlocks and resets all of its subtasks to open (`step false`).
- Changed top-bar task search on the home screen to open an `ALL TASKS` (`ALLE AUFGABEN`) view listing matching tasks across all six tiers (`Focus` through `Completed`) with active label filtering before returning to the previous tier pane on close.
- Changed the home screen top bar to center the active label name when a label filter is selected and smoothly animate it to the left when the search input expands.
- Changed the WebDAV synchronization trigger on the home screen into a secondary floating action button above the `+` task-add button when `WebDAV` or `Both` storage mode is active.
- Changed the Settings screen to group Local TDF and WebDAV configuration into Material 3 section cards, keep the `Save` and `Test Connection / Sync Now` footer fixed at the bottom, and auto-dismiss floating status banners after a few seconds.
- Changed the Raw TDF preview dialog title to `Raw TDF` and the WebDAV settings section heading to `WebDAV Synchronization` (`WebDAV-Synchronisation`).

### Fixed

- Fixed the quick-add bar `Labels` popup shifting `TierPageIndicator` upward by rendering the menu inside an anchored overlay portal.
- Fixed workspace and storage mode (`WebDAV` / `Both`) settings resetting to `Local` after restarting on Linux by persisting workspace settings in an atomic Base64-encoded binary keyring entry compatible with `gnome-keyring-daemon`.
- Fixed Linux and Windows native window, header bar, and taskbar titles to display `TierTask` instead of `tiertask`.
- Fixed Settings to disable the `Test Connection / Sync Now` button in `Local` storage mode and clear stale WebDAV status banners.
- Fixed ISO-8601 date and 24-hour timestamp parsing to reject out-of-range calendar rollover dates.

### Removed

- Removed the `Open Task Count` setting from Settings and workspace configuration.
- Removed preset filename recommendation chips (`tasks.tdf` and `t2.tdf`) from the Local TDF and WebDAV sections in Settings.
- Removed the landing greeting (`What's up!` / `Was steht an!`) and redundant tier navigation entries from the home screen and navigation drawer.
- Removed legacy Markdown (`.md`) parsing and serialization in favor of the TierTask Data Format (`.tdf`).
