---
name: spec-verification-loop
description: Runs a bounded (max 5 iterations), single-agent, non-oscillating verification and resolution loop on any Spec or TEP until zero defects remain or a hard abort triggers root-cause analysis. Triggered by /verify-spec <filepath> or /tep <filepath>.
---

# Bounded Spec & TEP Verification Loop

Execute this exact loop for any specification (`Spec`) or TierTask Enhancement Proposal (`TEP`) under `AGENTS.md` rules.

## 1. Hard Loop Invariants
1. **Iteration Cap (`MAX_ITERATIONS = 5`):** Maximum 4 resolution passes followed by final Audit Pass 5. Reaching Pass 5 with `defect_count > 0` triggers hard abort (`ERR_CONVERGENCE_FAILED`). Never run background polling loops.
2. **Single-Agent Execution:** Run every read, audit, and edit directly in this conversation. NEVER call `invoke_subagent`.
3. **Evidence-Only Anti-Hallucination Gate:** Every defect MUST cite `[Target <file>:<lines>]` and, for contradictions or baseline drift, `[Conflicting Source <file>:<lines>]`. Immediately discard uncited claims, stylistic nitpicks, alternative preferences, and out-of-scope hypotheticals.
4. **Presumption of Validity & Immutable `Decision Ledger`:** Internally coherent, defect-free existing design choices are valid by default and MUST NOT be replaced. Record every resolved ambiguity or user clarification as an append-only `LOCKED` entry:
   `[DECISION-XX | Iter N | LOCKED | <Target Section/Lines>]: <Committed rule and rationale>`
   Subsequent iterations are STRICTLY FORBIDDEN from questioning, reopening, or reversing any `LOCKED` entry.
5. **Oscillation & Stagnation Circuit Breaker (`ERR_OSCILLATION_DETECTED`):** Abort immediately (do not wait for Iteration 5) if any iteration `N >= 2`:
   - modifies, questions, or reverts a `LOCKED` decision,
   - re-reports a defect targeted in Iteration `N - 1`, or
   - fails to strictly reduce defects (`defect_count(N) >= defect_count(N - 1)`).

## 2. Pre-Loop Scope Alignment & Pillars
1. **Direct Inspect:** Outline the target (`python3 .agents/scripts/tiertask_dev.py outline <filepath>`) and read relevant sections directly to determine subject, lifecycle stage, and referenced baselines.
2. **Upfront Clarification:** If verification focus, target baseline, or a foundational domain premise is underspecified, ask the user FIRST (`ask_question` for multi-option choices or concise plain text) and seed answers as `LOCKED` entries in `Decision Ledger` before `Iteration 1`.
3. **Three Verification Pillars (adapted to document scope):**
   - **Coherence:** Internal consistency across sections, terminology, models, states, and examples; alignment with referenced normative baselines (respecting intentional TEP changes).
   - **Defect-Freedom:** Logical, technical, formal/grammatical, and structural accuracy; zero invalid assumptions, broken cross-references, unreachable states, or rule violations.
   - **Completeness:** Deterministic specification of required sections, boundaries, resource limits, error paths, and edge cases; zero `TBD`/`TODO` placeholders or incompatible ambiguities.

## 3. Execution Loop (`Iteration 1` to `5`)
Initialize `iteration = 1`, `previous_defect_count = infinity`, and `Decision Ledger` (with any upfront user answers). Repeat automatically without pausing for intermediate user approval:

### Step 3.1: Audit & Filter
Audit the target directly against the three pillars and agreed scope. Filter every candidate through Invariants 3 and 4 (discard uncited, stylistic, preference-based, or `LOCKED`-touching items) to compute `defect_count`.

### Step 3.2: Gate
- **Case A (`defect_count == 0`):** Stop immediately and output Section 4.A (`CONVERGED (PASS)`).
- **Case B (Circuit Breaker or Cap Hit):** Stop immediately WITHOUT applying partial edits and output Section 4.B:
  - If `iteration >= 2` and (`defect_count >= previous_defect_count` OR a `LOCKED` clause/prior defect reappeared) -> `ERR_OSCILLATION_DETECTED`.
  - Else if `iteration == 5` (`defect_count > 0`) -> `ERR_CONVERGENCE_FAILED`.
- **Case C (`0 < defect_count < previous_defect_count` and `iteration < 5`):** Proceed to Step 3.3.

### Step 3.3: Resolve & Lock
For each verified defect, apply one definitive fix directly to the file using strict precedence:
1. Explicit user instructions and `LOCKED` `Decision Ledger` entries.
2. Applicable project invariants (`AGENTS.md`, `ARCHITECTURE.md`, `spec/TDF_SPEC_0.8.0.md`).
3. Target Spec/TEP's own stated goals and primary design intent.
4. Simplest deterministic resolution closing the gap or contradiction.

Leave zero `TBD` placeholders or competing options. Append each committed resolution to `Decision Ledger`, set `previous_defect_count = defect_count`, increment `iteration += 1`, and immediately run Step 3.1.

## 4. Output Formats

### A. On Success (`CONVERGED (PASS)`)
1. **Status:** `CONVERGED (PASS)` in `N / 5` iterations.
2. **Evaluated Scope:** Target file and applied verification scope.
3. **Iteration Log:** One line per iteration (`Iter 1: 4 defects fixed -> Iter 2: 0 defects (Clean)`).
4. **Locked Decision Ledger:** All `DECISION-XX` entries anchored during the run.

### B. On Hard Abort (`ERR_CONVERGENCE_FAILED` / `ERR_OSCILLATION_DETECTED`)
1. **Status:** `HARD ABORT: ERR_CONVERGENCE_FAILED (Limit 5/5 reached)` or `HARD ABORT: ERR_OSCILLATION_DETECTED`.
2. **Unresolved Defects:** Exact section, line numbers, pillar, and description of each remaining defect.
3. **Root-Cause Analysis:** Structural cause (e.g., *Conflicting Axioms*, *Missing Domain Premise*, or *Cascade Effect*).
4. **Locked Decisions Preserved:** All valid `DECISION-XX` entries settled before abort.
5. **Required User Decision:** Concrete binary options (`Option A` vs. `Option B`) to break the deadlock before re-running.
