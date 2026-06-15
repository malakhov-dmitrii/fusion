# fusion

**A multi-model consensus planner for coding agents.** Claude, Codex, and DeepSeek (or any models you reach through [opencode](https://opencode.ai) — GLM, Kimi, MiniMax…) each draft a plan **independently**, cross-verify one another ("idiot-test"), and **must reach consensus** before a single plan is emitted. The output is a plan — fusion never touches your code.

> **Status: v0.1, experimental.** The harness (`fan` / `cross-verify` / `collect` / `cleanup`) is verified working across Claude, Codex, and opencode (incl. an opencode-only roster of GLM + Kimi + DeepSeek), and the full `/fusion` cycle runs end-to-end. It's young — flags and ergonomics will change — but the core mechanism is the point, not a finished product.

## Why

One frontier model has one set of blind spots. Three different model *families*, forced to debate and agree, cover for each other — the "fusion beats frontier" idea, applied to planning instead of answers. fusion makes the disagreement explicit and refuses to emit a plan until the models actually converge (or escalates the fork to you).

This is not a marginal quality bump. A single agent routinely hallucinates specifics — a flag, an API, a cost number — believes its own fiction, and ships something that does not work. The cross-verify rotation and the hard consensus gate exist to catch exactly that. fusion's own design and plan (in [`docs/`](docs/superpowers/specs)) were built this way, and the process caught real errors a solo agent had already written down as fact: a fabricated cost figure, a transport that did not survive a spike, a "read-only writes" contradiction, a missing `.gitignore`. That gap — between a grounded plan and confident fiction — is the whole point.

## How it works

```
brief (raw repo context, not a Claude summary)
   │
   ▼
fan ──► claude   ┐
        codex    │ each drafts a full plan, independently, challenging
        deepseek ┘ "don't build it / simpler / depends on future / scenarios"
   │
   ▼
cross-verify  (rotation — nobody grades themselves)
   claude → codex's plan,  codex → deepseek's,  deepseek → claude's
   each re-checks every claim INSTRUMENTALLY (grep/read/counter-example)
   │
   ▼
consensus gate  (hard: all agree on material axes, no majority override)
   split survives → spike the assumption → re-discuss → operator breaks the tie
   │
   ▼
synthesize  → plan.md  (+ debate.md: who proposed what, how it resolved)
```

Two invariants make it trustworthy:
- **Hard consensus gate.** No plan is emitted until every available model agrees on the material axes (architecture, approach, key assumptions). A 2-of-3 majority never overrides a dissenter; an unresolved fork goes to you (`decision: operator_decision`), never silently averaged.
- **Write isolation.** Planning is read-only. A git guard snapshots your repo before and after every fan; if a model mutates a tracked file, the run stops (`write_leak: true`).

See a real run in [`examples/selftest-plan.md`](examples/selftest-plan.md).

## Quickstart

```bash
git clone <this-repo> fusion && cd fusion
./install.sh                 # detects Claude Code / Codex, links the skill
# authenticate the providers in your roster (below), then:
/fusion <task> --dir <path-to-your-repo>
```

## Installing with your coding agent

Point your agent at this and it can install fusion itself:

> Clone `<repo-url>`, run `./install.sh` from the repo root, then read `README.md` →
> "Providers & auth" and make sure the CLIs for my chosen roster are authenticated.
> Default roster is `claude codex deepseek`. Confirm `/fusion` is available and report back.

## Requirements & providers

You only need the CLIs for the models in your roster.

| Participant | CLI | Auth | Smoke test |
|---|---|---|---|
| Claude | [`claude`](https://docs.claude.com/claude-code) | Claude Code login or `ANTHROPIC_API_KEY` | `claude -p "say OK"` |
| Codex / GPT | [`codex`](https://developers.openai.com/codex/cli) | `codex login` (ChatGPT) or `OPENAI_API_KEY` | `codex exec "say OK"` |
| GLM / Kimi / DeepSeek / MiniMax… | [`opencode`](https://opencode.ai) | `opencode auth login` (OpenCode Go / OpenRouter) | `opencode run -m opencode-go/glm-5 "say OK"` |

`git`, `bash`, `shasum` are assumed. If a participant's CLI is missing or unauthenticated, fusion drops it and runs `degraded` (and labels the output as such — it won't pretend two models are three).

## Models & rosters

Everything is configured by environment variables — no config files:

| Var | Meaning | Default |
|---|---|---|
| `FUSION_ROSTER` | participant list | `claude codex deepseek` |
| `FUSION_MODEL_DEEPSEEK` | model for the `deepseek` alias | `opencode-go/deepseek-v4-pro` |
| `FUSION_MODEL_CLAUDE` | `--model` for `claude` | CLI default |
| `FUSION_TIMEOUT` | per-call timeout (s) | `300` |
| `FUSION_GUARD_REPO` | repo the write-guard watches | `$PWD` |
| `FUSION_SCRATCH` | scratch dir for model writes | `/tmp/fusion-scratch` |

A participant is `claude[:model]` · `codex` · `opencode:<model>` · `deepseek` (alias). So you can run a **fully opencode-only** ensemble of three different families:

```bash
export FUSION_ROSTER="opencode:opencode-go/glm-5 opencode:opencode-go/kimi-k2.7-code opencode:opencode-go/deepseek-v4-pro"
```

## Usage

```
/fusion <task> --dir <target-repo> [--depth lite|full]
```

Or drive the harness directly (no host needed):

```bash
bash skills/fusion/fusion.sh fan draft prompt.txt runs/r1 claude codex deepseek
bash skills/fusion/fusion.sh cross-verify codex runs/r1/draft/codex.md runs/r1
bash skills/fusion/fusion.sh collect runs/r1
bash skills/fusion/fusion.sh --help
```

Artifacts land in `<target-repo>/.fusion/runs/<timestamp>/`: a `*-plan.md` (the consensus plan, with ranked assumptions and explicit operator-unknowns) and a `*-debate.md` (the trail).

## Works in Claude Code and Codex

The harness is plain bash + CLI adapters, so the orchestrator host is interchangeable. `install.sh` links the skill into `~/.claude/skills/` (Claude Code, invoked as `/fusion`) and/or `~/.codex/skills/` (Codex reads `SKILL.md`). The only host-specific step is the operator interview — `AskUserQuestion` in Claude Code, a plain text question elsewhere.

## Limitations (read these)

- **Plan-only.** fusion writes plans, never code. Hand the plan to an executor (e.g. `forge`, `improve execute`).
- **Batch, not interactive.** A full run is multiple models × rounds — expect minutes, not seconds.
- **Costs more than one model.** Several models × rounds — reach for it when being wrong is expensive (architecture, migrations, irreversible or hard-to-reverse calls), not for quick edits.
- **Provider drift.** CLI flags and quotas change. Codex in particular has a usage quota and a strict `config.toml` (a bad `service_tier` will break `codex exec`).

## Internals & design

The full design, the decision log, and the implementation plan (themselves produced and reviewed *through fusion*) live in [`docs/superpowers/specs/`](docs/superpowers/specs).

## License

MIT © Dmitrii Malakhov
