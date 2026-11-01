# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Added `CategoryScreen` (`lib/ui/category_screen.dart`) and `TaskBoard.evaluateForContext` so tapping a category card on `HomeScreen` opens a dedicated page displaying the 3 derived `Focus` tasks for that category while keeping all scheduling, blocking, condition, and search filters active.
- Added `Categories` and `Locations` management panels (`ContextManagementSheet`) in the side navigation drawer to create, view, and delete categories and locations, with accent color selection via an interactive HSV color wheel (`ColorWheelPicker`) or direct `#RRGGBB` hex input, optional `color "<#RRGGBB>"` persistence on `.tdf` `location` blocks, and multi-select category and location `FilterChip` selectors in `QuickAddBar`.
- Added single-pass $O(N)$ TierTask Data Format (`.tdf`) lexical scanner, structural parser, and canonical `LF` serializer (`TdfService`) implementing [`TDF_SPEC.md`](TDF_SPEC.md) with all Section 7 resource bounds and Section 8 `TdfErrorKind` diagnostics.
- Added `TaskCondition` (`DayTaskCondition`, `TimeWindowTaskCondition`), `TdfCategory`, and `TdfLocation` models (`lib/models/tdf_metadata.dart`) and dynamic 6-tier evaluation (`TaskBoard.evaluate`) with `subtasks auto-finish` checklist completion.
- Added `Open Task Count` (`Off` by default, `On`) setting to show or hide the total number of open tasks on category and location cards.
- Added storage mode selection (`Local`, `WebDAV`, `Both`), configurable local `.tdf` file name (`localFilePath`, defaulting to `tiertask.tdf`), and local filesystem persistence via `LocalFileRepository`.
- Added color theme selection (`System`, `Light`, `Dark`) in Settings with `System` as the default mode.
- Added English (`en`, default) and German (`de`) localization via external ARB files (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`) with `System`, `English`, and `Deutsch` language selection in Settings.
- Added Linux, Android, and Windows platform support for the 6-tier task board.

### Changed
- Changed persistence across `LocalFileRepository`, `WebDavRepository`, `SecureSettingsRepository`, `WebDavConfig`, and `TaskNotifier` to store and synchronize `.tdf` documents (`tiertask.tdf` / `t2.tdf`) with primary local persistence.
- Changed `QuickAddBar` to match the landing page color palette and provide a task input field, mutually exclusive `Priority` (on/off) and `Someday` (on/off) toggle buttons, an `Advanced` button opening an extended view for defining subtasks, and an `Add` button enabled only when input text is present.
- Changed `HomeScreen` into a streamlined landing page displaying the top greeting (`What's up!` / `Was steht an!`), minimalist `Focus` task cards, dynamic `Categories` and `Locations` carousels sourced from `.tdf` `category` and `location` blocks (automatically hidden when empty), a top-right search filter with a conditional WebDAV sync icon (`WebDAV` or `Both` storage mode), and a top-left navigation drawer housing secondary tiers and actions.
- Changed status banners in Settings (save confirmation, WebDAV connection success, and synchronization error messages) to fade out and dismiss automatically after a few seconds.
- Changed the localized application title (`appTitle`) from `TierTask (T2)` to `TierTask`.
- Changed UI tier headings, tab labels, quick-add chips, and restore/move sheet items to display localized tier names (`Focus`, `Ready`, `Planned`, `Blocked`, `Someday`, `Completed`).

### Removed
- Removed Markdown (`.md`) parsing, serialization, and `MarkdownService` in favor of the TierTask Data Format (`.tdf`).

### Fixed
- Fixed Linux and Windows native window, header bar, and taskbar titles to display `TierTask` instead of `tiertask`.
- Fixed Settings to disable the `Test Connection / Sync Now` button in `Local` storage mode and clear stale status banners so WebDAV connection success is never displayed when WebDAV is unconfigured or invalid.
- Fixed ISO-8601 date and 24-hour timestamp parsing in `TaskItem` and `TdfService` to reject out-of-range calendar rollover dates.
