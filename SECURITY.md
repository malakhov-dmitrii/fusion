# Security

## Reporting

Found something? Open a [private security advisory](../../security/advisories/new), or email the maintainer listed in `git log`. Please don't file public issues for vulnerabilities.

## What fusion does and doesn't touch

- **No secrets are stored.** fusion shells out to `claude`, `codex`, and `opencode`; authentication is entirely theirs (their login or `*_API_KEY` env). fusion never reads, writes, or logs credentials.
- **Planning is read-only.** During `fan`/`cross-verify`, a git guard snapshots the target repo before and after each call. If a tracked file changes, the run stops (`write_leak: true`).
- **Spikes are isolated.** `spike` runs in a throwaway `git worktree` that is always removed; write access is confined to that worktree, never your working tree.
- **Prompts include repo content.** The brief sends real file excerpts to the model providers in your roster. Don't point fusion at a repo whose contents you can't send to those providers, and review your roster before running on sensitive code.
