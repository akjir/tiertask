---
name: spec-verification-loop
description: Executes a bounded, non-oscillating verification and resolution loop on any specification (Spec) or TierTask Enhancement Proposal (TEP) for coherence, defect-freedom, and completeness until zero defects remain or a hard iteration limit triggers an error abort with root-cause analysis. Triggered via `/verify-spec <filepath>` or `/tep <filepath>`.
---

# Bounded Spec & TEP Verification Loop

Execute this identical workflow whether the user provides a specification (`Spec`) or a TierTask Enhancement Proposal (`TEP`). Follow all rules in `AGENTS.md` strictly.

## 1. Core Loop Invariants & Hard Bounds

To prevent infinite loops, hallucinated flaws, and circular re-evaluations, enforce these five invariants across the entire execution:

1. **Hard Iteration & Runaway Cap (`MAX_ITERATIONS = 5`):** The verification loop MUST NOT exceed 5 iterations (up to 4 resolution passes followed by Audit Pass 5). Reaching Iteration 5 with `defect_count > 0` is a hard failure (`ERR_CONVERGENCE_FAILED`). Never spawn nested loops inside sub-agents or run background polling loops.
2. **Anti-Hallucination Gate (Evidence-Backed Defects Only):** NEVER invent flaws, stylistic nitpicks, alternative design preferences, or hypothetical edge cases outside the document's scope. Every defect MUST cite the exact target location (`[Target <file>:<lines>]`) and, for contradictions or baseline deviations, the conflicting clause (`[Conflicting Source <file>:<lines>]`). Uncited or subjective findings are invalid and discarded immediately. If zero valid defects exist in an iteration, declare **`CONVERGED (PASS)`** and terminate the loop immediately.
3. **Presumption of Validity & Immutable Decision Ledger (No Flip-Flopping):**
   - Existing design choices in the target Spec or TEP that are internally coherent and free of defects are **valid by default** and MUST NOT be questioned or replaced with alternative preferences.
   - Maintain an append-only `Decision Ledger` across iterations. Whenever an ambiguity, gap, or discrepancy is resolved (by user clarification before the loop or by engineering resolution in Iteration `N`), record the decision (`DECISION-01`, `DECISION-02`, ...) as **`LOCKED`**. Subsequent iterations (and any delegated sub-agents) are STRICTLY FORBIDDEN from questioning, reopening, or reversing a `LOCKED` decision.
4. **Oscillation & Stagnation Circuit Breaker:** Trigger an immediate hard abort (`ERR_OSCILLATION_DETECTED`) without waiting for Iteration 5 if any iteration (`N >= 2`):
   - Attempts to modify, question, or revert a clause already settled in the `Decision Ledger`,
   - Fails to resolve a defect targeted in Iteration `N - 1` (the same clause/defect reappears), or
   - Increases or fails to reduce the total defect count (`defect_count(N) >= defect_count(N - 1)`).
5. **Single-Controller & Sub-Agent Isolation (`P-SUBAGENT-ISOLATION`):** The parent agent is the sole loop controller, decision authority, and file writer. Delegated sub-agents (if used) MUST execute single-pass, read-only audits only, receive the full `Decision Ledger` in their prompt, and never edit the target file or run their own verification loops.

## 2. Pre-Loop Scope Alignment & Core Evaluation Pillars

### 2.1 Individual Scope & User Clarification Gate (Before `Iteration 1`)
What is audited depends on the specific Spec or TEP and the user's intent:
1. Read the target Spec or TEP (using `tiertask_dev.py outline` and targeted `read_file` ranges) to determine its subject matter, lifecycle stage, and referenced baseline documents.
2. **Clarify Upfront When Needed:** If the verification focus, target baseline, or a foundational domain decision in the Spec/TEP is unclear or underspecified by the user, **ask the user first** (via `ask_question` or concise plain text) before entering the loop. Record any user answers in the `Decision Ledger` as `LOCKED` baseline premises so the loop runs deterministically without guessing.

### 2.2 The Three Core Verification Pillars
Evaluate the target Spec or TEP identically across these three universal pillars, adapted to the document's individual scope:

1. **Coherence (Kohärenz):**
   - Internal consistency across all sections, definitions, terminology, data models, state transitions, and examples (Clause A never contradicts Clause B).
   - Consistency with any normative baseline documents or architectural rules referenced by or applicable to the Spec/TEP (while respecting that a TEP proposes intentional additions/changes).
2. **Defect-Freedom / Correctness (Fehlerfreiheit):**
   - Logical, technical, grammatical/formal, and structural accuracy.
   - Absence of invalid technical assumptions, broken cross-references, unreachable states, or rule violations.
3. **Completeness (Komplettheit):**
   - All required sections, boundary conditions, resource limits, error/failure paths, and edge cases relevant to the document's scope are deterministically specified.
   - Absence of unresolved gaps, "TBD" / "TODO" placeholders, or ambiguous behavior where multiple incompatible interpretations remain possible.

## 3. Unified Iterative Execution Protocol (`Iteration 1` to `MAX_ITERATIONS`)

After completing Section 2.1, initialize `iteration = 1`, `previous_defect_count = infinity`, and `Decision Ledger` (seeded with any upfront user clarifications). Repeat the following cycle for the target Spec or TEP while `iteration <= 5`:

### Step 3.1: Evidence-Based Audit Pass
- Audit the current state of the target Spec or TEP against the three pillars in Section 2.2 (**Coherence**, **Defect-Freedom**, **Completeness**) and the agreed scope.
- If delegating read-only sub-agents, pass the current `Decision Ledger`, agreed scope, and Section 2.2 pillars in their prompt and collect their raw findings.
- Filter every candidate finding through the Anti-Hallucination Gate and `Decision Ledger`:
  - Discard any finding that lacks an exact `[Target <file>:<lines>]` citation (and `[Conflicting Source <file>:<lines>]` for contradictions).
  - Discard any finding that is purely stylistic, questions a valid existing design choice, or touches a `LOCKED` decision.
  - Count the remaining verified defects (`defect_count`).

### Step 3.2: Convergence & Circuit-Breaker Gate
- **Case A (`defect_count == 0`):**
  - Stop the loop immediately.
  - Output the **Final Convergence Report** (Section 4.A).
- **Case B (`iteration == MAX_ITERATIONS` OR `defect_count >= previous_defect_count` OR a `LOCKED` clause/prior defect reappeared):**
  - Stop the loop immediately. Do NOT apply partial, unverified edits in the failing pass.
  - Output the **Hard Abort & Root-Cause Analysis Report** (Section 4.B).
- **Case C (`defect_count > 0` and `iteration < MAX_ITERATIONS` and `defect_count < previous_defect_count`):**
  - Proceed to Step 3.3.

### Step 3.3: Decisive Resolution & Ledger Lock
- For each verified defect, make a single, definitive engineering decision using this deterministic precedence order:
  1. Explicit user instructions and `LOCKED` entries in the `Decision Ledger`,
  2. Applicable project/architectural invariants (`AGENTS.md`, `ARCHITECTURE.md`, `spec/TDF_SPEC_0.6.0.md` where relevant to the document),
  3. The target Spec/TEP's own stated goals and primary design intent,
  4. Simplest deterministic solution that closes the gap or contradiction.
- Do NOT leave open questions, "TBD" placeholders, or multiple competing options in the document.
- Apply the exact fixes to the target Spec or TEP file.
- Append each resolution to the `Decision Ledger`:
  `[DECISION-XX | Iter N | LOCKED | <Target Section/Lines>]: <Exact committed rule and rationale>`.
- Set `previous_defect_count = defect_count`, increment `iteration += 1`, and immediately execute the next iteration.

## 4. Mandatory Output Formats

### A. On Success (`CONVERGED (PASS)`)
Output a concise summary containing:
1. **Status:** `CONVERGED (PASS)` in `N / 5` iterations.
2. **Evaluated Scope:** Target file (`Spec` or `TEP`) and applied verification scope.
3. **Iteration Log:** 1-line summary per iteration showing the number of defects found and fixed across Coherence, Defect-Freedom, and Completeness (e.g., `Iter 1: 4 defects fixed -> Iter 2: 1 defect fixed -> Iter 3: 0 defects (Clean)`).
4. **Locked Decision Ledger:** List of all `DECISION-XX` choices permanently anchored during the run.

### B. On Hard Abort (`ERR_CONVERGENCE_FAILED` or `ERR_OSCILLATION_DETECTED`)
When the loop hits `MAX_ITERATIONS` (5) or detects oscillation/stagnation, terminate with an explicit error and output this root-cause analysis:
1. **Status:** `HARD ABORT: ERR_CONVERGENCE_FAILED (Limit 5/5 reached)` or `HARD ABORT: ERR_OSCILLATION_DETECTED`.
2. **Unresolved Defects:** Exact section headers, line numbers, pillar (`Coherence`, `Defect-Freedom`, or `Completeness`), and descriptions of the remaining issues.
3. **Root-Cause Analysis (Why It Ran Out of Bounds):**
   - Explain the structural reason convergence failed (e.g., *Conflicting Axioms:* Requirement X and Requirement Y are mutually exclusive; *Missing Domain Premise:* Fixing section A requires a product decision not derivable from the document; *Cascade Effect:* Resolving Defect A in Iter 1 invalidated Section B in Iter 2).
4. **Locked Decisions Preserved:** All valid `DECISION-XX` entries settled before the abort.
5. **Required User Decision to Break Deadlock:** Formulate concrete, binary options (`Option A` vs. `Option B`) for the user to resolve the root cause before re-running the skill.
