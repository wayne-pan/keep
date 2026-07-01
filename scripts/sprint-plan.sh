#!/usr/bin/env bash
# sprint-plan.sh — Structured PLAN.md + task-brief file manager for sprint.
#
# Plan artifacts (PLAN.md, per-task briefs, reports, review packages) live in
# a session-scoped TEMP DIR — never inside the project tree. This keeps git
# status clean and matches the "files > pasted text" subagent contract.
#
# Cross-platform temp dir resolution (Linux / macOS / Windows-native / Git Bash / Cygwin):
#   KEEP_SPRINT_TMP  >  TMPDIR  >  TEMP  >  TMP  >  /tmp
# On Windows-native bash, TMPDIR is usually unset but TEMP/TMP point to
# %USERPROFILE%\AppData\Local\Temp. On Git Bash /tmp is mapped; on Cygwin both
# forms work. Honoring all four env vars covers every harness.
#
# Usage:
#   sprint-plan init                          # Create session plan dir, anchor it, print path
#   sprint-plan path                          # Print current plan dir (read from anchor)
#   sprint-plan write-plan                    # Read structured PLAN.md from stdin, write to temp dir
#   sprint-plan show-plan                     # Print PLAN.md absolute path (error if missing)
#   sprint-plan task-brief <N>                # Extract Task N slice → task-N-brief.md, print path
#   sprint-plan task-report <N>               # Print task-N-report.md path (touch empty if missing)
#   sprint-plan review-package <BASE> <HEAD>  # Write git diff → review-<BASE>-<HEAD>.md, print path
#   sprint-plan clear                         # rm -rf session plan dir + remove anchor

set -euo pipefail

# ── Cross-platform temp root ──
SPRINT_TMP="${KEEP_SPRINT_TMP:-${TMPDIR:-${TEMP:-${TMP:-/tmp}}}}"

# ── Session identity (sanitized for filesystem safety) ──
# Allowlist [A-Za-z0-9._-]; anything else becomes '_'. Prevents path traversal
# via SESSION_ID='../../home' → PLAN_DIR outside the temp root → destructive clear.
SESSION_ID_RAW="${KEEP_SESSION_ID:-${SESSION_ID:-default}}"
SESSION_ID=$(printf '%s' "$SESSION_ID_RAW" | tr -c 'A-Za-z0-9._-' '_')
PLAN_DIR="$SPRINT_TMP/keep-sprint-${SESSION_ID}"

# ── Anchor file (in project .sprint/) so sibling calls rediscover the temp dir ──
# Records the exact absolute path chosen at init time — survives later env changes.
SPRINT_DIR=".sprint"
PLAN_ANCHOR="$SPRINT_DIR/PLAN_TMP_PATH"

# Resolve the temp dir, with safety checks. Used by every command that consumes
# the path — especially `clear`, which destructively removes it.
# Validates: (a) anchor is not a symlink, (b) resolved path is inside the
# expected temp root and contains our 'keep-sprint-' prefix.
resolve_plan_dir() {
  local path
  if [ -L "$PLAN_ANCHOR" ]; then
    echo "Refusing: $PLAN_ANCHOR is a symlink" >&2
    exit 1
  fi
  if [ -f "$PLAN_ANCHOR" ]; then
    path=$(cat "$PLAN_ANCHOR" 2>/dev/null || echo "")
  else
    path="$PLAN_DIR"
  fi
  # Safety: path must live under the temp root and contain our prefix.
  # Blocks both anchor-tampering and SESSION_ID traversal even if one check misses.
  case "$path" in
    "$SPRINT_TMP"*/keep-sprint-*) ;;
    *)
      echo "Refusing: unsafe plan dir '$path' (expected under $SPRINT_TMP with keep-sprint- prefix)" >&2
      exit 1
      ;;
  esac
  printf '%s' "$path"
}

need_plan_file() {
  local p="$1"
  [ -f "$p" ] || { echo "Missing: $p (did you 'sprint-plan write-plan' first?)" >&2; exit 1; }
}

# Extract Task N from PLAN.md.
# Convention: tasks are H2 headings `## Task N: <title>` or `## Task N. <title>`.
# Brief runs from that heading until the next `^## ` or `^# ` heading.
extract_task() {
  local plan="$1" n="$2" out="$3"
  awk -v n="$n" '
    BEGIN { in_task = 0 }
    /^##[[:space:]]/ {
      # Match: ## Task <n>[:.] [title]
      if ($0 ~ ("^##[[:space:]]*Task[[:space:]]*" n "([:.]?[[:space:]]|$)")) {
        in_task = 1; print; next
      }
      # Any other H2 ends the slice
      if (in_task) exit
    }
    /^#[[:space:]]/ && in_task { exit }   # H1 ends slice
    in_task { print }
  ' "$plan" > "$out"
}

cmd="${1:-}"
shift || true

case "$cmd" in
  init)
    mkdir -p "$PLAN_DIR" "$SPRINT_DIR"
    # Resolve to absolute path so the anchor is portable across `cd` shifts
    abs_dir=$(cd "$PLAN_DIR" 2>/dev/null && pwd -P || echo "$PLAN_DIR")
    echo "$abs_dir" > "$PLAN_ANCHOR"
    echo "$abs_dir"
    ;;

  path)
    echo "$(resolve_plan_dir)"
    ;;

  write-plan)
    [ -t 0 ] && { echo "Error: stdin is a terminal. Pipe PLAN.md content." >&2; exit 1; }
    target_dir="$(resolve_plan_dir)"
    mkdir -p "$target_dir"
    cat > "$target_dir/PLAN.md"
    echo "$target_dir/PLAN.md"
    ;;

  show-plan)
    target_dir="$(resolve_plan_dir)"
    need_plan_file "$target_dir/PLAN.md"
    echo "$target_dir/PLAN.md"
    ;;

  task-brief)
    n="${1:?task number required (e.g. 3)}"
    # Validate integer before interpolating into awk regex — prevents
    # n='.*' / '1|2' / '' from matching unintended task headings.
    case "$n" in
      ''|*[!0-9]*)
        echo "Error: task number must be a positive integer (got: '$n')" >&2
        exit 1
        ;;
    esac
    target_dir="$(resolve_plan_dir)"
    plan="$target_dir/PLAN.md"
    need_plan_file "$plan"
    brief="$target_dir/task-$n-brief.md"
    extract_task "$plan" "$n" "$brief"
    if [ ! -s "$brief" ]; then
      echo "Task $n not found in $plan" >&2
      echo "Expected heading: '## Task $n: ...' or '## Task $n. ...'" >&2
      rm -f "$brief"
      exit 1
    fi
    echo "$brief"
    ;;

  task-report)
    n="${1:?task number required}"
    target_dir="$(resolve_plan_dir)"
    mkdir -p "$target_dir"
    report="$target_dir/task-$n-report.md"
    [ -f "$report" ] || touch "$report"
    echo "$report"
    ;;

  review-package)
    base="${1:?BASE commit required}"
    head="${2:?HEAD commit required}"
    target_dir="$(resolve_plan_dir)"
    mkdir -p "$target_dir"
    # Sanitize for filename (slashes from branch names etc.)
    safe_base=$(printf '%s' "$base" | tr -c 'A-Za-z0-9._-' '_')
    safe_head=$(printf '%s' "$head" | tr -c 'A-Za-z0-9._-' '_')
    pkg="$target_dir/review-${safe_base}-${safe_head}.md"
    {
      echo "# Review Package: ${base}..${head}"
      echo
      echo "Generated: $(date -Iseconds 2>/dev/null || date)"
      echo
      echo "## Commits"
      echo
      git log --oneline "${base}..${head}" 2>/dev/null || echo "(git log failed — bad range?)"
      echo
      echo "## Diff Stat"
      echo
      git diff --stat "${base}..${head}" 2>/dev/null || echo "(git diff --stat failed)"
      echo
      echo "## Full Diff (unified, 10 lines context)"
      echo
      git diff -U10 "${base}..${head}" 2>/dev/null || echo "(git diff failed)"
    } > "$pkg"
    echo "$pkg"
    ;;

  clear)
    target_dir="$(resolve_plan_dir)"
    rm -rf "$target_dir"
    rm -f "$PLAN_ANCHOR"
    echo "Cleared: $target_dir"
    ;;

  ""|-h|--help|help)
    cat << 'EOF'
sprint-plan.sh — Structured PLAN.md + task-brief manager (temp dir, cross-platform)

Commands:
  init                          Create session plan dir, write anchor, print path
  path                          Print current plan dir
  write-plan                    Read PLAN.md from stdin → temp dir
  show-plan                     Print PLAN.md path
  task-brief <N>                Extract Task N → task-N-brief.md, print path
  task-report <N>               Print task-N-report.md path (touch if missing)
  review-package <BASE> <HEAD>  Write git diff → review-<..>.md, print path
  clear                         rm -rf plan dir + anchor

Env:
  KEEP_SPRINT_TMP  Override temp root (highest priority)
  TMPDIR / TEMP / TMP  Standard env vars (auto-detected)
  KEEP_SESSION_ID / SESSION_ID  Per-sprint isolation (default: "default")

Anchor:
  .sprint/PLAN_TMP_PATH records the temp dir chosen at init. Sibling commands
  read it back so the path survives env changes mid-sprint.
EOF
    ;;

  *)
    echo "Unknown command: $cmd" >&2
    echo "Run 'sprint-plan help' for usage." >&2
    exit 1
    ;;
esac
