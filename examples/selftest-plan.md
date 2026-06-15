# Example: a real `/fusion` run

> This file is **actual output** from running `/fusion` on this repo (task: "add a `selftest`
> subcommand to fusion.sh"). It ran `degraded: two-model` because Codex was unavailable
> (broken local `config.toml`), so Claude + DeepSeek-V4-Pro reached consensus and the plan
> was synthesized from their two drafts + cross-verification. `decision: consensus`.
>
> It shows what fusion produces: a synthesized plan, ranked assumptions, operator-unknowns,
> and a debate trail — not a single model's guess.

---

## Task
Add a `selftest` subcommand to `fusion.sh`: run `cleanup`, then a trivial `fan` smoke
(one participant, prompt "say OK"), assert exit 0 + non-empty stdout, print PASS/FAIL + return code.

## Constraints (union of both drafts, deduped)
- One file, no new dependencies, no changes to existing command signatures.
- Reuse existing `cmd_cleanup` and `cmd_fan`; do not duplicate adapter logic.

## Chosen solution (consensus)
Add `cmd_selftest()` right after `cmd_cleanup()`, plus one `case` arm in `main()`. The function:
1. `cmd_cleanup` (idempotent — already is).
2. Write a throwaway prompt (`say OK`) to a temp file under `$SCRATCH`.
3. `cmd_fan selftest <prompt> <tmp-run-dir> "$participant"` (default participant configurable, see assumptions).
4. Read `<tmp-run-dir>/selftest/<slug>.exit` and `.md`: PASS iff exit `0` **and** stdout non-empty.
5. Print `PASS`/`FAIL` + the participant's exit code; `return 0` on PASS else `1`.

## Alternatives considered → rejected
- **Standalone test outside `fusion.sh`** (DeepSeek raised): rejected — selftest should ship with the tool and exercise the real `fan` path, not a parallel copy.
- **Hardcode `codex`** (task's literal): softened — codex may be unavailable (it was, this run). Use a configurable participant defaulting to codex; report which participant ran.

## Implementation steps
| # | file | change | est-loc | depends-on |
|---|------|--------|---------|------------|
| 1 | `skills/fusion/fusion.sh` | add `cmd_selftest()` after `cmd_cleanup()` | ~15 | – |
| 2 | `skills/fusion/fusion.sh` | add `selftest) cmd_selftest "$@" ;;` to `main()` + usage line | ~2 | 1 |
| 3 | — | verify: `bash skills/fusion/fusion.sh selftest` → `PASS`, `echo $?` = 0 | – | 1,2 |

## Assumptions (ranked)
- **HIGH** — `cmd_fan` writes `<dir>/<role>/<slug>.{exit,md}` (verified: it does).
- **MED** — default participant is reachable on the host; if not, selftest should FAIL loudly, not hang (300s timeout covers hang).
- **LOW / UNVERIFIED** — DeepSeek's cross-verify of the Claude draft truncated before emitting a verdict; its edge-case coverage for this plan is unconfirmed.

## Operator-unknowns
- Which participant should `selftest` default to, given any one may be down? (recommendation: try the first reachable in `$FUSION_ROSTER`.)

## Hard boundaries / STOP
- Do not add network calls beyond the single model smoke. If `cmd_fan` contract changes, STOP and update selftest in lockstep.

## Cross-verification (folded in, 0 blockers)
Claude→DeepSeek plan: `issues-found` (3 MAJOR, 4 MINOR) — edge cases (participant down, empty stdout vs exit 0), a scope contradiction, prompt-injection note. All non-blocking; addressed above as assumptions/boundaries.

---
`decision: consensus` · `degraded: two-model (codex unavailable)` · participants: claude, deepseek-v4-pro
