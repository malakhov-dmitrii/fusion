#!/usr/bin/env bash
# fusion.sh — minimal multi-model fan-out harness (v1).
# Dumb pipe: fan / cross-verify / collect / cleanup. Orchestrator (any host) lives outside this script.
#
# A participant is "<kind>[:<model>]":
#   claude[:<model>]        -> claude -p [--model <model>]
#   codex                   -> codex exec --sandbox read-only   (model via ~/.codex/config.toml)
#   opencode:<model>        -> opencode run -m <model>          (deepseek-v4-pro, opencode-go/glm-5, .../kimi-k2.7-code, ...)
#   deepseek                -> alias for opencode:$FUSION_MODEL_DEEPSEEK
# opencode participants run under the read-only `plan` agent (FUSION_OPENCODE_AGENT),
# NOT the default `build` agent — a build agent has skill/subagent/write access and
# will re-invoke the `fusion` skill from inside a participant, causing recursion.
# Rosters are just participant lists, e.g.:
#   mixed:        claude codex deepseek
#   opencode-only: opencode:opencode-go/glm-5 opencode:opencode-go/kimi-k2.7-code opencode:opencode-go/deepseek-v4-pro
# ponytail: status.json built with printf, not jq — fine for v1.
set -uo pipefail

RUN_ROOT="${FUSION_RUN_ROOT:-.fusion/runs}"
TIMEOUT="${FUSION_TIMEOUT:-300}"
SCRATCH="${FUSION_SCRATCH:-/tmp/fusion-scratch}"

_slug() { printf '%s' "$1" | tr '/:' '__'; }   # participant -> safe filename

# _run <participant> <promptfile>  — dispatch one model call, answer to stdout
_run() {
  local participant="$1" pfile="$2"
  local kind="${participant%%:*}" model=""
  [ "$participant" != "$kind" ] && model="${participant#*:}"
  case "$kind" in
    claude)   claude -p ${model:+--model "$model"} "$(cat "$pfile")" ;;
    codex)    codex exec --sandbox read-only "$(cat "$pfile")" ;;
    deepseek) opencode run --pure --agent "${FUSION_OPENCODE_AGENT:-plan}" --dir "$SCRATCH" \
                -m "${FUSION_MODEL_DEEPSEEK:-opencode-go/deepseek-v4-pro}" "$(cat "$pfile")" ;;
    opencode|oc)
              [ -n "$model" ] || { echo "opencode participant needs a model: opencode:<model>" >&2; return 98; }
              opencode run --pure --agent "${FUSION_OPENCODE_AGENT:-plan}" --dir "$SCRATCH" -m "$model" "$(cat "$pfile")" ;;
    *) echo "unknown participant kind: $kind" >&2; return 99 ;;
  esac
}

# signature of target repo's tracked state — detect write-leaks from participants
_repo_sig() { git -C "${FUSION_GUARD_REPO:-$PWD}" status --porcelain 2>/dev/null | shasum | awk '{print $1}'; }

# fan <role> <promptfile> <dir> <participant...>  — parallel, write-guarded, status.json
cmd_fan() {
  local role="$1" prompt="$2" dir="$3"; shift 3
  mkdir -p "$dir/$role" "$SCRATCH"
  local sig_before sig_after leak=false p slug
  sig_before="$(_repo_sig)"
  for p in "$@"; do
    slug="$(_slug "$p")"
    ( timeout "$TIMEOUT" bash "$0" _run "$p" "$prompt" \
        >"$dir/$role/$slug.md" 2>"$dir/$role/$slug.err"
      echo "$?" >"$dir/$role/$slug.exit" ) &
  done
  wait
  sig_after="$(_repo_sig)"
  if [ "$sig_before" != "$sig_after" ]; then
    leak=true
    echo "WRITE-LEAK: target repo mutated during fan — a participant wrote tracked files" >&2
  fi
  _status "$dir" "$role" "$leak" "$@"
  [ "$leak" = true ] && return 3 || return 0
}

# cross-verify <verifier-participant> <target-plan-file> <dir> — idiot-test one plan
cmd_cross_verify() {
  local verifier="$1" target="$2" dir="$3"
  mkdir -p "$dir/cross"
  local vslug; vslug="$(_slug "$verifier")"
  local base; base="$(basename "$target" .md)"
  local pf="$dir/cross/prompt-$vslug-on-$base.txt"
  {
    echo "Ты — кросс-верификатор. Автор плана ниже НЕКОМПЕТЕНТЕН: перепроверь ИНСТРУМЕНТАЛЬНО"
    echo "(grep/read/контрпример, не «перечитал и согласен»). Оси проверки:"
    echo "correctness · completeness · assumptions · contradictions · missed-risks."
    echo "Формат КАЖДОЙ находки ровно: [BLOCKER|MAJOR|MINOR] <axis> @<секция> — <суть> — <пруф>."
    echo "Последняя строка ровно: VERDICT: verified|issues-found|blocked (blockers=<N>)."
    echo "--- ПЛАН: ---"
    cat "$target"
  } >"$pf"
  ( timeout "$TIMEOUT" bash "$0" _run "$verifier" "$pf" \
      >"$dir/cross/$vslug-on-$base.md" 2>"$dir/cross/$vslug-on-$base.err"
    echo "$?" >"$dir/cross/$vslug-on-$base.exit" )
}

# collect <run-dir> — concat artifacts into aggregate.md
cmd_collect() {
  local dir="$1" out="$1/aggregate.md" f
  { echo "# Aggregate — $dir"; echo
    for f in "$dir"/*/*.md; do
      [ -f "$f" ] || continue
      echo "## $f"; echo '```'; cat "$f"; echo '```'; echo
    done
  } >"$out"
  echo "$out"
}

# cleanup [--all] — remove orphan fusion worktrees + scratch
cmd_cleanup() {
  git worktree list 2>/dev/null | awk '/fusion-spike/{print $1}' | while read -r w; do
    git worktree remove --force "$w" 2>/dev/null || true
  done
  rm -rf "$SCRATCH" 2>/dev/null || true
  echo "cleanup done"
}

# spike <hypothesis> <dir> [participant]  — test an assumption in a throwaway git worktree
# (write-enabled but isolated; the worktree is always removed). Prints a VERDICT line.
cmd_spike() {
  local hyp="$1" dir="$2" participant="${3:-deepseek}"
  mkdir -p "$dir/spikes"
  local slug; slug="$(printf '%s' "$hyp" | tr -c 'a-zA-Z0-9' '_' | cut -c1-48)"
  local out="$dir/spikes/$slug.md" repo wt rc
  repo="$(git -C "${FUSION_GUARD_REPO:-$PWD}" rev-parse --show-toplevel 2>/dev/null || true)"
  wt="$(mktemp -d "${TMPDIR:-/tmp}/fusion-spike-XXXXXX")"
  [ -n "$repo" ] && git -C "$repo" worktree add --detach -q "$wt" HEAD 2>/dev/null || true
  local prompt="Проверь гипотезу ИНСТРУМЕНТАЛЬНО в этой изолированной рабочей копии (можно создавать throwaway-код, запускать команды). Гипотеза: $hyp. Последняя строка ровно: VERDICT: confirmed|refuted|inconclusive — <evidence>."
  local kind="${participant%%:*}" model=""; [ "$participant" != "$kind" ] && model="${participant#*:}"
  ( cd "$wt" || exit 97
    case "$kind" in
      claude)      timeout "$TIMEOUT" claude -p ${model:+--model "$model"} "$prompt" ;;
      codex)       timeout "$TIMEOUT" codex exec --sandbox workspace-write "$prompt" ;;
      deepseek)    timeout "$TIMEOUT" opencode run -m "${FUSION_MODEL_DEEPSEEK:-opencode-go/deepseek-v4-pro}" "$prompt" ;;
      opencode|oc) timeout "$TIMEOUT" opencode run -m "$model" "$prompt" ;;
      *) echo "spike: unknown participant $participant" >&2; exit 99 ;;
    esac
  ) >"$out" 2>"$dir/spikes/$slug.err"; rc=$?
  echo "$rc" >"$dir/spikes/$slug.exit"
  [ -n "$repo" ] && git -C "$repo" worktree remove --force "$wt" 2>/dev/null || true
  rm -rf "$wt"
  grep -E '^VERDICT:' "$out" 2>/dev/null || echo "VERDICT: inconclusive — no verdict line (exit $rc)"
}

# selftest [participant]  — cleanup + a trivial fan smoke; prints PASS/FAIL, exit 0 on PASS
cmd_selftest() {
  local participant="${1:-codex}" dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/fusion-selftest-XXXXXX")"
  cmd_cleanup >/dev/null 2>&1 || true
  printf 'Reply with exactly: OK\n' >"$dir/p.txt"
  cmd_fan selftest "$dir/p.txt" "$dir" "$participant" >/dev/null 2>&1 || true
  local slug ex bytes; slug="$(_slug "$participant")"
  ex="$(cat "$dir/selftest/$slug.exit" 2>/dev/null || echo 99)"
  bytes="$(wc -c <"$dir/selftest/$slug.md" 2>/dev/null || echo 0)"
  rm -rf "$dir"
  if [ "$ex" = 0 ] && [ "${bytes:-0}" -gt 0 ]; then
    echo "PASS — $participant: exit 0, ${bytes} bytes"; return 0
  fi
  echo "FAIL — $participant: exit $ex, ${bytes} bytes"; return 1
}

_usage() {
  cat <<'USAGE'
fusion.sh — minimal multi-model fan-out harness

  fan <role> <promptfile> <dir> <participant...>   run participants in parallel (write-guarded)
  cross-verify <verifier> <target-plan> <dir>      idiot-test one plan
  spike <hypothesis> <dir> [participant]           test an assumption in a throwaway worktree
  collect <dir>                                    concat run artifacts into aggregate.md
  selftest [participant]                           smoke the harness; PASS/FAIL
  cleanup                                          remove orphan worktrees + scratch

  participant = claude[:model] | codex | opencode:<model> | deepseek
USAGE
}

# _status <dir> <role> <leak> <participant...>
_status() {
  local dir="$1" role="$2" leak="${3:-false}"; shift 3
  local sf="$dir/status.json" p slug ex st first=1
  { printf '{"run_dir":"%s","role":"%s","write_leak":%s,"participants":{' "$dir" "$role" "$leak"
    for p in "$@"; do
      slug="$(_slug "$p")"
      ex="$(cat "$dir/$role/$slug.exit" 2>/dev/null || echo 99)"
      case "$ex" in 0) st=ok ;; 124) st=timeout ;; *) st=error ;; esac
      [ $first -eq 1 ] || printf ','; first=0
      printf '"%s":{"exit":%s,"status":"%s"}' "$p" "$ex" "$st"
    done
    printf '}}'
  } >"$sf"
  cat "$sf"
}

main() {
  local cmd="${1:-help}"; shift || true
  case "$cmd" in
    _run)         _run "$@" ;;
    fan)          cmd_fan "$@" ;;
    cross-verify) cmd_cross_verify "$@" ;;
    spike)        cmd_spike "$@" ;;
    collect)      cmd_collect "$@" ;;
    selftest)     cmd_selftest "$@" ;;
    cleanup)      cmd_cleanup "$@" ;;
    help|-h|--help) _usage ;;
    *) _usage >&2; exit 1 ;;
  esac
}
main "$@"
