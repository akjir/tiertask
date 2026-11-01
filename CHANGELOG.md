# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Added Linux, Android, and Windows platform support for the 6-tier Markdown task board.
- Added specifications for generic WebDAV synchronization and local Markdown (`.md`) file persistence.

### Fixed
- Fixed ISO-8601 completion date parsing (`YYYY-MM-DD`) in `MarkdownService` and `TaskItem` to reject out-of-range calendar rollover dates.
