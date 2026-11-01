# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Added `Open Task Count` (`Off` by default, `On`) setting to show or hide the total number of open tasks on category and location cards.
- Added storage mode selection (`Local`, `WebDAV`, `Both`), configurable local Markdown file name (`localFilePath`, defaulting to `tiertask.md`), and local filesystem persistence via `LocalFileRepository`.
- Added color theme selection (`System`, `Light`, `Dark`) in Settings with `System` as the default mode.
- Added English (`en`, default) and German (`de`) localization via external ARB files (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`) with `System`, `English`, and `Deutsch` language selection in Settings.
- Added Linux, Android, and Windows platform support for the 6-tier Markdown task board.
- Added specifications for generic WebDAV synchronization and local Markdown (`.md`) file persistence.

### Changed
- Changed `QuickAddBar` to match the landing page color palette and provide a task input field, mutually exclusive `Priority` (on/off) and `Someday` (on/off) toggle buttons, an `Advanced` button opening an extended view for defining subtasks, and an `Add` button enabled only when input text is present.
- Changed `HomeScreen` into a streamlined landing page displaying the top greeting (`What's up!` / `Was steht an!`), minimalist `Focus` task cards, horizontal `Categories` and `Locations` cards with configurable solid accent bars (without completion progress bars), a top-right search filter with a conditional WebDAV sync icon (`WebDAV` or `Both` storage mode), and a top-left navigation drawer housing secondary tiers and actions.
- Changed status banners in Settings (save confirmation, WebDAV connection success, and synchronization error messages) to fade out and dismiss automatically after a few seconds.
- Changed the localized application title (`appTitle`) from `TierTask (T2)` to `TierTask`.
- Changed UI tier headings, tab labels, quick-add chips, and restore/move sheet items to display localized tier names (`Focus`, `Ready`, `Planned`, `Blocked`, `Someday`, `Completed`) without Markdown `# [n]` prefixes.
- Changed the Markdown task board schema to six numbered tiers (`# [1] Focus`, `# [2] Ready`, `# [3] Planned`, `# [4] Blocked`, `# [5] Someday`, `# [6] Completed`), matching headings strictly by tier number (`1`–`6`), ignoring label text on parse, and creating missing tiers automatically on serialization.

### Fixed
- Fixed Linux and Windows native window, header bar, and taskbar titles to display `TierTask` instead of `tiertask`.
- Fixed Settings to disable the `Test Connection / Sync Now` button in `Local` storage mode and clear stale status banners so WebDAV connection success is never displayed when WebDAV is unconfigured or invalid.
- Fixed ISO-8601 completion date parsing (`YYYY-MM-DD`) in `MarkdownService` and `TaskItem` to reject out-of-range calendar rollover dates.
