---
name: fusion
description: Multi-model consensus planner — Claude + Codex + DeepSeek independently draft a plan, cross-verify each other ("idiot-test"), and must reach consensus on material axes before any plan is emitted. Use when a non-trivial task needs a maximally hardened plan (research, alternatives, spikes, operator interview), not a quick answer. Output is a plan; implementation is out of scope (hand to forge/improve).
---

# fusion — multi-model consensus planner

Claude + Codex + DeepSeek V4 Pro (or any models you reach through opencode) **independently** draft a plan, cross-verify one another, and **must reach consensus** on the material axes before a plan is emitted. Premise: an ensemble of different families beats one frontier model because their blind spots differ.

The orchestrator is **the host model** (Claude Code or Codex) running this playbook. All participants (`claude`/`codex`/`deepseek`/…) are called the same way through `fusion.sh` (CLI adapters), so the orchestrator is not privileged and **does not decide by majority**: consensus is computed mechanically from votes, and a tie is broken by the operator. The skill therefore behaves identically under any host.

## When to use
A non-trivial task that needs a hardened plan with real alternatives and checked assumptions. **Not** for quick answers or trivial edits — it is a batch tool (expect minutes, multiple models × rounds), not interactive.

## Invariants (never break)
- **Hard consensus gate:** synthesize only when every available participant is `reached` on the material axes (architecture · approach · key-assumptions). A 2-of-3 majority never overrides a dissenter.
- **`decision ∈ {consensus, operator_decision, blocked, degraded}`** — a plan after an operator tie-break is `operator_decision`, never `consensus`.
- **Raw brief, not your summary** — participants must not see "the repo through the host's eyes", or the host's blind spots become shared.
- **`<2` families available → `degraded`,** never presented as fusion.
- **`write_leak: true` in status.json → STOP** and investigate (a participant mutated the target repo).

## Parameters
`/fusion <task> --dir <target-repo> [--depth lite|full]`  (lite = 1 round, full = 2; default full)

**Roster (configurable, `$FUSION_ROSTER`)** — the participant list, passed to every `fan`/`cross-verify`:
- mixed (default): `claude codex deepseek`
- opencode-only: `opencode:opencode-go/glm-5 opencode:opencode-go/kimi-k2.7-code opencode:opencode-go/deepseek-v4-pro`
- participant = `claude[:model] | codex | opencode:<model> | deepseek`. Cross-verify rotation = cyclic shift of the roster (i verifies i+1).
- opencode/deepseek participants run under the read-only `plan` agent (`$FUSION_OPENCODE_AGENT`, default `plan`) so they **draft** instead of acting — the default `build` agent has skill/subagent/write access and re-invokes the `fusion` skill from inside a participant, causing recursion.

## Playbook

Throughout: `export FUSION_GUARD_REPO=<target> FUSION_SCRATCH=/tmp/fusion-$TS; RUN=<target>/.fusion/runs/$TS; SH=skills/fusion/fusion.sh`.

### 0. Setup
`bash "$SH" cleanup` — remove orphan worktrees + scratch. `mkdir -p $RUN`.

### 1. Brief (RAW)
Build `$RUN/brief.md` from raw material: repo tree (depth-capped), `git -C <target> rev-parse HEAD` + recent log, ADR/CONTEXT/README (capped), task-relevant files (grep/glob), intent docs. Compute `coverage = included/candidates`: <50% → warn the operator; <20% → `BLOCKED: insufficient-context`. No host annotation — raw only.

### 2. Round 1 — draft
Build `$RUN/draft-prompt.txt` = brief + task + a **multi-angle requirement** (consider: don't solve it / solve it much simpler / it depends on future plans / different scenarios — the first vector isn't always stable).
- `bash "$SH" fan draft $RUN/draft-prompt.txt $RUN claude codex deepseek` — all in parallel, write-guarded.
- Check `$RUN/status.json`: `write_leak=true` → STOP; `<2` participants `ok` → `degraded`.

### 3. Round 1 — cross-verify (rotation; nobody grades themselves)
All through `fusion.sh` (parallelizable — distinct models/files); the contract is baked into the command (axes correctness/completeness/assumptions/contradictions/missed-risks + a `VERDICT:` line):
- `bash "$SH" cross-verify deepseek $RUN/draft/claude.md $RUN`   (DeepSeek → Claude's plan)
- `bash "$SH" cross-verify codex $RUN/draft/deepseek.md $RUN`    (Codex → DeepSeek's plan)
- `bash "$SH" cross-verify claude $RUN/draft/codex.md $RUN`      (Claude → Codex's plan)

### 4. Aggregate
`bash "$SH" collect $RUN` → `$RUN/aggregate.md`.

### 5. Round 2 (depth=full) — re-discuss + structured votes
`git -C <target> rev-parse HEAD` — drift-check: if HEAD moved, re-snapshot the brief and flag `drifted:true`.
Re-discuss prompt: each participant sees the whole `aggregate.md`, revises / leans toward an option / raises a DISAGREE, and **must end with a votes block**:
```
VOTES:
architecture:    reached|split | material:true|false | position:<…> | evidence:<path|none> | would_accept_if:<…>
approach:        …
key-assumptions: …
```
`bash "$SH" fan rediscuss …` → cross-verify again (same rotation).

### 6. Consensus gate (mechanical, from VOTES)
- For each material axis (`material:true`): are all available participants `reached`? → axis converged.
- A material axis still `split` → if there's a spikeable assumption, `bash "$SH" spike "<hypothesis>" $RUN <participant>` → structured verdict (`confirmed|refuted|inconclusive`): `confirmed/refuted` updates positions; `inconclusive` → mark the assumption `confidence=LOW`, surface it `UNVERIFIED` in the plan, don't let that point block. Allow one extra re-discuss on the affected axis.
- Not converged after the cap (draft-rounds=2, +1 post-spike) → **operator breaks the tie** (real fork only; `AskUserQuestion` in Claude Code, a plain text question elsewhere) → `decision=operator_decision`. Operator unavailable → `decision=blocked`, emit `BLOCKED: no-consensus` with each side's position.
- `material:false` axes (effort/risk/cosmetics) do not gate → record as ranked-assumption / noted objection.
- All material axes `reached` → `decision=consensus`.

### 7. Synthesize (mechanical template)
Only when `decision ∈ {consensus, operator_decision}`. Fill the template from raw artifacts — **every claim/boundary/assumption → a source path**, add no new claims:

Problem · Constraints (union, deduped) · Chosen solution (the consensus approach; for operator_decision, the operator's call) · Alternatives + why-rejected · Implementation steps `[{file, description, est-loc, depends-on:[idx]}]` · Assumptions ranked (HIGH/MED/LOW = agreement × instrumental backing) · Operator-unknowns · Hard boundaries + STOP · Git stamp + drift status · `decision:`.
→ `$RUN/final/<topic>-plan.md`

`debate.md` = a mechanical join: disagreements across all rounds + a resolution table (consensus / spike / operator). → `$RUN/final/<topic>-debate.md`.

## Degraded / failures
- timeout/exit≠0/empty → `fan` already retried; mark `timeout/error`, continue if ≥2.
- codex `quota` → drop it (gpt-via-OpenRouter fallback is a v2 idea).
- 2 families → `degraded: two-model`: cross-verify is mutual, no majority exists → any unresolved material split → operator.
- 1 family → `degraded: claude-only`, `DEGRADED` in the plan title, not presented as fusion.
- spike `refuted` → blocks the dependent branch; `inconclusive` → LOW/UNVERIFIED, no block.
