# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/).

## [Unreleased]

## [0.1.0] — 2026-06-15

First public cut. Experimental.

### Added
- `fusion.sh` harness: `fan` (parallel, write-guarded), `cross-verify` (structured idiot-test), `spike` (isolated git worktree), `collect`, `selftest`, `cleanup`.
- Host-agnostic adapters: `claude[:model]`, `codex`, `opencode:<model>`, `deepseek` — so an all-opencode roster (GLM + Kimi + DeepSeek) works with no Claude or Codex.
- `SKILL.md` playbook with a hard consensus gate (no majority override) and operator tie-break.
- `install.sh` for Claude Code and Codex; MIT license; design docs; a real run example.

### Known gaps
- ROI vs a single model is not yet measured (baseline A/B pending — see `docs/`).
- `SKILL.md` cross-verify quality varies by provider; treat a missing `VERDICT:` line as inconclusive.
