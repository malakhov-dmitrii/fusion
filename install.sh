#!/usr/bin/env bash
# Install the fusion skill for your coding agent. Idempotent: safe to re-run.
# Detects Claude Code and/or Codex and links the skill into their skills dir.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_SRC="$HERE/skills/fusion"
[ -d "$SKILL_SRC" ] || { echo "error: $SKILL_SRC not found (run from the repo root)"; exit 1; }

link() {  # link <skills-dir> <host-label> <invoke-hint>
  mkdir -p "$1"
  ln -sfn "$SKILL_SRC" "$1/fusion"
  echo "  ✓ $2: linked $1/fusion   $3"
}

echo "Installing fusion skill…"
installed=0
if [ -d "$HOME/.claude" ] || command -v claude >/dev/null 2>&1; then
  link "$HOME/.claude/skills" "Claude Code" "→ run /fusion in a session"; installed=1
fi
if [ -d "$HOME/.codex" ] || command -v codex >/dev/null 2>&1; then
  link "$HOME/.codex/skills" "Codex" "→ Codex reads ~/.codex/skills/fusion/SKILL.md"; installed=1
fi
if [ "$installed" -eq 0 ]; then
  echo "  ! No Claude Code or Codex host detected — skill not linked."
  echo "    You can still drive the harness directly:  bash skills/fusion/fusion.sh --help"
  echo "    (e.g. an opencode-only roster needs no host skill dir.)"
fi

echo
echo "Model CLIs (install only the ones in your roster):"
for c in claude codex opencode; do
  if command -v "$c" >/dev/null 2>&1; then echo "  ✓ $c"; else echo "  – $c  (optional)"; fi
done

echo
echo "Next:"
echo "  1. Authenticate the providers you'll use (README → Providers & auth)."
echo "  2. Pick a roster (README → Models & rosters); default is: claude codex deepseek"
echo "  3. Run:  /fusion <task> --dir <repo>      (or: bash skills/fusion/fusion.sh --help)"
