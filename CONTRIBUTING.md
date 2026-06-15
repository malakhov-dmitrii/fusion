# Contributing to fusion

Thanks for looking. fusion is small on purpose — a bash harness plus a playbook. Keep changes minimal and verifiable.

## Architecture in one minute

- **`skills/fusion/fusion.sh`** — a deterministic "dumb pipe". It only runs model CLIs in parallel, captures their output, and guards the repo. No orchestration logic lives here.
- **`skills/fusion/SKILL.md`** — the playbook the host model (Claude Code / Codex) follows: build a brief, fan, cross-verify, run the consensus gate, synthesize.

The split matters: anything stateful or "smart" goes in `SKILL.md`; `fusion.sh` stays mechanical and testable.

## The adapter contract

A participant is `claude[:model] | codex | opencode:<model> | deepseek`. All dispatch through one place:

```sh
_run <participant> <promptfile>   # reads the prompt file, writes the model's answer to stdout
```

To **add a provider**, add one `case` arm to `_run` (and to `cmd_spike`, which needs a write-enabled invocation). Nothing else should need to know about it. Keep models configurable by env, not hardcoded.

## Artifact layout

A run writes to `runs/<ts>/`:

```
brief.md · draft/<slug>.md · cross/<slug>-on-<plan>.md · spikes/<slug>.md · status.json
```

`status.json` carries `write_leak`, per-participant `{exit,status}`, and (in a full cycle) the votes. `collect` concatenates everything into `aggregate.md`. Filenames are slugged from the participant string (`/` and `:` → `_`).

## Local dev (no agent needed)

```sh
bash -n skills/fusion/fusion.sh                 # syntax
shellcheck -S error skills/fusion/fusion.sh     # lint
bash skills/fusion/fusion.sh selftest deepseek  # live smoke (needs that provider authed)
bash skills/fusion/fusion.sh --help
```

CI runs the first three (without the live model call) on every PR.

## Pull requests

- Keep the diff small and the harness mechanical.
- `bash -n` and `shellcheck -S error` must pass; run `selftest` against at least one provider you have.
- Update `README.md` / `SKILL.md` if behavior changes, and add a `CHANGELOG.md` entry under *Unreleased*.
