# TierTask Enhancement Proposals (TEP)

This directory serves as the collaborative feature roadmap and specification hub between developer and AI assistant, modeled after OpenJDK Enhancement Proposals (JEP 0). Significant features, cross-layer architectural changes, and especially modifications to [`TDF_SPEC.md`](../../TDF_SPEC.md) are tracked as individual, version-controlled TierTask Enhancement Proposals (`TEP-XXX`).

> [!IMPORTANT]
> **Explicit Trigger & Scope Rule:** A TEP is created **only** when the `/tep` skill is invoked (or when the user explicitly confirms a TEP recommendation). Minor UI adjustments, bug fixes, localization wording changes, and small refactorings do not use a TEP and are implemented directly via **`tiertask-dev-workflow`**.

## Proposal Board

### Active Proposals

| ID | Title | Type | Status | Specification |
| :--- | :--- | :--- | :--- | :--- |
| TEP-001 | Agent-Optimized Codebase Architecture, Acyclic Import DAG, and Sub-5s TDD Harness | architecture | review | [`tep-001-agent-optimized-architecture.md`](tep-001-agent-optimized-architecture.md) |

### Completed Proposals

| ID | Title | Type | Status | Specification |
| :--- | :--- | :--- | :--- | :--- |

## Status Lifecycle

```text
concept ---> planned ---> in-progress ---> review ---> completed
                                                   \--> rejected
```

* **`concept`:** Initial proposal, motivation, goals/non-goals, and exploratory approach (Part 1).
* **`planned`:** Concrete specification, `TDF_SPEC.md` schema impact, affected modules, localization keys (`en`/`de`), and `M-*` TDD test strategy agreed upon (Part 2).
* **`in-progress`:** Baseline test suites (`flutter test` and `flutter analyze --fatal-infos --fatal-warnings`) verified green; actively being implemented following strict Red-Green-Refactor TDD.
* **`review`:** All unit and widget tests (`flutter test`), static analysis (`flutter analyze --fatal-infos --fatal-warnings`), and formatting (`dart format --output=none --set-exit-if-changed lib test`) passing; `TDF_SPEC.md`, `README.md`, `ARCHITECTURE.md`, `AGENTS.md`, and `CHANGELOG.md` synchronized; awaiting manual user review and approval.
* **`completed`:** Manually reviewed and approved by the user; finalized and retained permanently for historical rationale and traceability.
* **`rejected`:** Decided against, with documented reasoning.

## Workflow & Guidelines

Refer to the **`tep`** skill in [`.agents/skills/tep/SKILL.md`](../skills/tep/SKILL.md) for standard procedures on creating, recommending, updating, and advancing TierTask Enhancement Proposals.
