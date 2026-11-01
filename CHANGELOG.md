# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Added English (`en`, default) and German (`de`) localization via external ARB files (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`) with `System`, `English`, and `Deutsch` language selection in Settings.
- Added Linux, Android, and Windows platform support for the 6-tier Markdown task board.
- Added specifications for generic WebDAV synchronization and local Markdown (`.md`) file persistence.

### Changed
- Changed the Markdown task board schema to six numbered tiers (`# [1] Focus`, `# [2] Ready`, `# [3] Planned`, `# [4] Blocked`, `# [5] Someday`, `# [6] Completed`), matching headings strictly by tier number (`1`–`6`), ignoring label text on parse, and creating missing tiers automatically on serialization.

### Fixed
- Fixed ISO-8601 completion date parsing (`YYYY-MM-DD`) in `MarkdownService` and `TaskItem` to reject out-of-range calendar rollover dates.
