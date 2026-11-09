# TierTask Enhancement Proposals (TEP)

This directory serves as the collaborative feature roadmap and specification hub between developer and AI assistant, modeled after OpenJDK Enhancement Proposals (JEP 0). Significant features, cross-layer architectural changes, and especially modifications to [`spec/TDF_SPEC_0.6.0.md`](../../spec/TDF_SPEC_0.6.0.md) are tracked as individual, version-controlled TierTask Enhancement Proposals (`TEP-XXX`).

> [!IMPORTANT]
> **Explicit Trigger & Scope Rule:** A TEP is created **only** when the `/tep` skill is invoked (or when the user explicitly confirms a TEP recommendation). Minor UI adjustments, bug fixes, localization wording changes, and small refactorings do not use a TEP and are implemented directly via **`tiertask-dev-workflow`**.

## Proposal Board

### Active Proposals

| ID | Title | Type | Status | Specification |
| :--- | :--- | :--- | :--- | :--- |
| TEP-004 | TDF 0.6.0 Runtime, Synchronization, and UI Conformance Implementation | feature | review | [`tep-004-tdf-0-6-0-implementation.md`](tep-004-tdf-0-6-0-implementation.md) |
| TEP-005 | Selectable Location Source Resolution, Offline Open Location Code Decoding, and Forward Geocoding Disambiguation | feature | review | [`tep-005-location-source-resolution.md`](tep-005-location-source-resolution.md) |
| TEP-006 | TDF Specification 0.7.0 Exploratory Design and Idea Collection | spec | concept | [`tep-006-tdf-spec-0-7-0.md`](tep-006-tdf-spec-0-7-0.md) |

### Completed Proposals

| ID | Title | Type | Status | Specification |
| :--- | :--- | :--- | :--- | :--- |
| TEP-001 | Agent-Optimized Codebase Architecture, Acyclic Import DAG, and Sub-5s TDD Harness | architecture | completed | [`tep-001-agent-optimized-architecture.md`](tep-001-agent-optimized-architecture.md) |
| TEP-002 | Structured Diagnostic Logging, Configurable Log Levels, and Local/WebDAV Log Persistence | feature | completed | [`tep-002-structured-logging-and-persistence.md`](tep-002-structured-logging-and-persistence.md) |
| TEP-003 | TDF Specification 0.6.0 Exploratory Design and Conformance Roadmap | spec | completed | [`tep-003-tdf-spec-0-6-0.md`](tep-003-tdf-spec-0-6-0.md) |

## Status Lifecycle

```text
concept ---> planned ---> in-progress ---> review ---> completed
                                                   \--> rejected
```

* **`concept`:** Initial proposal, motivation, goals/non-goals, and exploratory approach (Part 1).
* **`planned`:** Concrete specification, `spec/TDF_SPEC_0.6.0.md` schema impact, affected modules, localization keys (`en`/`de`), and `M-*` TDD test strategy agreed upon (Part 2).
* **`in-progress`:** Baseline test suites (`flutter test` and `flutter analyze --fatal-infos --fatal-warnings`) verified green; actively being implemented following strict Red-Green-Refactor TDD.
* **`review`:** All unit and widget tests (`flutter test`), static analysis (`flutter analyze --fatal-infos --fatal-warnings`), and formatting (`dart format --output=none --set-exit-if-changed lib test`) passing; `spec/TDF_SPEC_0.6.0.md`, `README.md`, `ARCHITECTURE.md`, `AGENTS.md`, and `CHANGELOG.md` synchronized; awaiting manual user review and approval.
* **`completed`:** Manually reviewed and approved by the user; finalized and retained permanently for historical rationale and traceability.
* **`rejected`:** Decided against, with documented reasoning.

## Workflow & Guidelines

Refer to the **`tep`** skill in [`.agents/skills/tep/SKILL.md`](../skills/tep/SKILL.md) for standard procedures on creating, recommending, updating, and advancing TierTask Enhancement Proposals.
