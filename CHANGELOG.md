# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Added `TierPageIndicator` (`lib/ui/widgets/tier_page_indicator.dart`) and horizontal 6-tier `PageView` sliding (`Focus`, `Ready`, `Planned`, `Blocked`, `Someday`, `Completed`) on `HomeScreen`, rendering above `QuickAddBar` when the add button is pressed, showing dots for inactive tiers and an icon for the active tier over a transparent background, displaying the hovered tier icon in an intermediate color and a borderless tier name pill on desktop mouse-over without wave animation, supporting desktop Left/Right arrow key navigation, and applying a wave effect on hold and drag that enlarges the two adjacent neighbor dots (`1.5x` in the intermediate color) and jumps directly to the selected tier pane upon release.
- Added single-pass $O(N)$ TierTask Data Format (`.tdf`) lexical scanner, structural parser, and canonical `LF` serializer (`TdfService`) implementing [`TDF_SPEC.md`](TDF_SPEC.md) with all Section 7 resource bounds and Section 8 `TdfErrorKind` diagnostics.
- Added `TaskCondition` (`DayTaskCondition`, `TimeWindowTaskCondition`), `TdfCategory`, and `TdfLocation` models (`lib/models/tdf_metadata.dart`) and dynamic 6-tier evaluation (`TaskBoard.evaluate` and `TaskBoard.evaluateForContext`) with `subtasks auto-finish` checklist completion.
- Added `Open Task Count` (`Off` by default, `On`) setting in Settings.
- Added storage mode selection (`Local`, `WebDAV`, `Both`), configurable local `.tdf` file name (`localFilePath`, defaulting to `tiertask.tdf`), and local filesystem persistence via `LocalFileRepository`.
- Added color theme selection (`System`, `Light`, `Dark`) in Settings with `System` as the default mode.
- Added English (`en`, default) and German (`de`) localization via external ARB files (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`) with `System`, `English`, and `Deutsch` language selection in Settings.
- Added Linux, Android, and Windows platform support for the 6-tier task board.

### Changed
- Changed persistence across `LocalFileRepository`, `WebDavRepository`, `SecureSettingsRepository`, `WebDavConfig`, and `TaskNotifier` to store and synchronize `.tdf` documents (`tiertask.tdf` / `t2.tdf`) with primary local persistence.
- Changed `QuickAddBar` into a single-row inline bottom bar that replaces the circular `+` add button when clicked, featuring a borderless task title input on the left followed by `Priority`, `Someday`, upward-expanding `Categories` and `Locations` multi-select buttons, a placeholder `Advanced` button, and a `Cancel` button.
- Changed `HomeScreen` into a streamlined landing page displaying the top greeting (`What's up!` / `Was steht an!`), minimalist `Focus` task cards, a top-right search filter with a conditional WebDAV sync icon (`WebDAV` or `Both` storage mode), and a top-left navigation drawer housing secondary tiers and actions without `Categories` or `Locations` sections on the landing page or side panel.
- Changed status banners in Settings (save confirmation, WebDAV connection success, and synchronization error messages) to fade out and dismiss automatically after a few seconds.
- Changed the localized application title (`appTitle`) from `TierTask (T2)` to `TierTask`.
- Changed UI tier headings, tab labels, quick-add chips, and restore/move sheet items to display localized tier names (`Focus`, `Ready`, `Planned`, `Blocked`, `Someday`, `Completed`).

### Removed
- Removed Markdown (`.md`) parsing, serialization, and `MarkdownService` in favor of the TierTask Data Format (`.tdf`).

### Fixed
- Fixed Linux and Windows native window, header bar, and taskbar titles to display `TierTask` instead of `tiertask`.
- Fixed Settings to disable the `Test Connection / Sync Now` button in `Local` storage mode and clear stale status banners so WebDAV connection success is never displayed when WebDAV is unconfigured or invalid.
- Fixed ISO-8601 date and 24-hour timestamp parsing in `TaskItem` and `TdfService` to reject out-of-range calendar rollover dates.
