#!/usr/bin/env bash
# sprint-plan.sh — Structured PLAN.md + task-brief file manager for sprint.
#
# Everything lives under .sprint/ — one root, two scopes:
#   .sprint/<task>/   per-task: PLAN.md, STATE.yaml, CHECKPOINT.yaml, briefs,
#                     reports, review packages. One dir per sprint task, so
#                     different tasks never overwrite each other.
#   .sprint/ root     cross-sprint: KNOWLEDGE.md, FINDINGS.md, CODE_MAP.md,
#                     CURRENT (anchor naming the active task).
# .sprint/ is gitignored, keeping git status clean while matching the
# "files > pasted text" subagent contract.
#
# Usage:
#   sprint-plan init [name]                   # Create/reuse .sprint/<name>/, anchor it, print path
#   sprint-plan path                          # Print active task dir (read from anchor)
#   sprint-plan list                          # List task dirs (marks active)
#   sprint-plan write-plan                    # Read structured PLAN.md from stdin, write to task dir
#   sprint-plan show-plan                     # Print PLAN.md absolute path (error if missing)
#   sprint-plan task-brief <N>                # Extract Task N slice → task-N-brief.md, print path
#   sprint-plan task-report <N>               # Print task-N-report.md path (touch empty if missing)
#   sprint-plan review-package <BASE> <HEAD>  # Write git diff → review-<BASE>-<HEAD>.md, print path
#   sprint-plan clear                         # rm -rf active task dir + remove anchor

set -euo pipefail

# ── Locations ──
# Resolve the repo root so commands work from any subdirectory; fall back to
# CWD outside a git repo.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SPRINT_DIR="$REPO_ROOT/.sprint"
# Anchor: names the ACTIVE task (a single sanitized name, not a path). All
# sibling commands read it back — survives cd shifts and context compaction.
ANCHOR="$SPRINT_DIR/CURRENT"

# Names that would collide with cross-sprint files at the .sprint/ root.
RESERVED_NAMES="CURRENT KNOWLEDGE.md FINDINGS.md CODE_MAP.md SESSION_ID EXPERIMENTS.tsv TRIPLETS.jsonl"

# Sanitize for filesystem safety: allowlist [A-Za-z0-9._-]; anything else
# becomes '_'. Prevents path traversal via name='../../home' → dir escape.
sanitize_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

# A task name is valid iff: non-empty, no '.'/'..' identity, allowlisted
# charset only, and not reserved for cross-sprint files.
valid_name() {
  case "$1" in
    ""|"."|"..") return 1 ;;
    *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  local r
  for r in $RESERVED_NAMES; do
    [ "$1" = "$r" ] && return 1
  done
  return 0
}

# Resolve the active task dir, with safety checks. Used by every command that
# consumes the path — especially `clear`, which destructively removes it.
# Validates: (a) anchor is not a symlink, (b) anchored name passes the same
# traversal/charset/reserved checks as init, (c) the task dir itself is not a
# symlink, (d) resolved path stays inside .sprint (containment).
resolve_task_dir() {
  local name dir phys_root abs
  if [ -L "$ANCHOR" ]; then
    echo "Refusing: $ANCHOR is a symlink" >&2
    exit 1
  fi
  if [ ! -f "$ANCHOR" ]; then
    echo "No active sprint task (missing $ANCHOR). Run: sprint-plan init <name>" >&2
    exit 1
  fi
  name=$(cat "$ANCHOR" 2>/dev/null || echo "")
  if ! valid_name "$name"; then
    echo "Refusing: invalid task name in $ANCHOR: '$name'" >&2
    exit 1
  fi
  dir="$SPRINT_DIR/$name"
  if [ -L "$dir" ]; then
    echo "Refusing: $dir is a symlink" >&2
    exit 1
  fi
  if [ -d "$dir" ]; then
    abs=$(cd "$dir" && pwd -P)
    phys_root=$(cd "$SPRINT_DIR" && pwd -P)
    case "$abs" in
      "$phys_root"/*) printf '%s' "$abs" ;;
      *)
        echo "Refusing: resolved task dir '$abs' escapes $SPRINT_DIR" >&2
        exit 1
        ;;
    esac
  else
    # Dir missing: print the intended path (write-plan/task-report mkdir -p
    # it back into existence); the name is already validated above.
    printf '%s' "$dir"
  fi
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
    name_arg="${1:-}"
    if [ -n "$name_arg" ]; then
      name=$(sanitize_name "$name_arg")
    else
      # Default: timestamped slug — guarantees a fresh dir per sprint, so
      # unnamed inits never overwrite a previous task.
      name="sprint-$(date +%Y%m%d-%H%M%S)"
    fi
    if ! valid_name "$name"; then
      echo "Error: task name '$name' is reserved or invalid — pick another name." >&2
      exit 1
    fi
    if [ -f "$ANCHOR" ] && [ ! -L "$ANCHOR" ]; then
      prev=$(cat "$ANCHOR" 2>/dev/null || echo "")
      [ "$prev" = "$name" ] || echo "Note: switching active task from '$prev' to '$name' (previous dir kept)" >&2
    fi
    mkdir -p "$SPRINT_DIR/$name"
    printf '%s' "$name" > "$ANCHOR"
    (cd "$SPRINT_DIR/$name" && pwd -P)
    ;;

  path)
    echo "$(resolve_task_dir)"
    ;;

  list)
    if [ ! -d "$SPRINT_DIR" ]; then
      echo "(no .sprint dir yet)"
      exit 0
    fi
    active=""
    [ -f "$ANCHOR" ] && [ ! -L "$ANCHOR" ] && active=$(cat "$ANCHOR" 2>/dev/null || echo "")
    found=0
    for d in "$SPRINT_DIR"/*/; do
      [ -d "$d" ] || continue
      n=$(basename "$d")
      if [ "$n" = "$active" ]; then
        echo "$n  <- active"
      else
        echo "$n"
      fi
      found=1
    done
    if [ "$found" -eq 0 ]; then
      echo "(no task dirs)"
    fi
    ;;

  write-plan)
    [ -t 0 ] && { echo "Error: stdin is a terminal. Pipe PLAN.md content." >&2; exit 1; }
    target_dir="$(resolve_task_dir)"
    mkdir -p "$target_dir"
    cat > "$target_dir/PLAN.md"
    echo "$target_dir/PLAN.md"
    ;;

  show-plan)
    target_dir="$(resolve_task_dir)"
    need_plan_file "$target_dir/PLAN.md"
    echo "$target_dir/PLAN.md"
    ;;

  tasks)
    target_dir="$(resolve_task_dir)"
    plan="$target_dir/PLAN.md"
    need_plan_file "$plan"
    # Scan for `## Task N` headings; emit `n\ttitle`. BSD-awk compatible —
    # no gawk match($0, /pat/, arr); use sub() + index-friendly split.
    tasks_out=$(awk '
      /^##[[:space:]]*Task[[:space:]]*[0-9]+/ {
        line = $0
        sub(/^##[[:space:]]*Task[[:space:]]*/, "", line)
        # Reject non-integer task numbers (e.g. 1.5) — align with extract_task,
        # which requires N followed by [:. ], so listing and brief-extraction
        # agree on what counts as "Task N".
        if (line !~ /^[0-9]+([:.]?[[:space:]]|$)/) next
        n = line; sub(/[/:.].*$/, "", n); sub(/[[:space:]].*$/, "", n)
        title = line
        # strip leading "N[:.][space]" prefix to get just the title
        sub(/^[0-9]+[:.]?[[:space:]]*/, "", title)
        print n "\t" title
      }
    ' "$plan")
    if [ -z "$tasks_out" ]; then
      echo "No tasks found in PLAN.md" >&2
      exit 0
    fi
    while IFS=$'\t' read -r n title; do
      brief_status="n"; report_status="n"
      [ -f "$target_dir/task-$n-brief.md" ] && brief_status="y"
      [ -f "$target_dir/task-$n-report.md" ] && report_status="y"
      printf '%-4s brief=%s  report=%s  %s\n' "$n" "$brief_status" "$report_status" "$title"
    done <<< "$tasks_out"
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
    target_dir="$(resolve_task_dir)"
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
    target_dir="$(resolve_task_dir)"
    mkdir -p "$target_dir"
    report="$target_dir/task-$n-report.md"
    [ -f "$report" ] || touch "$report"
    echo "$report"
    ;;

  review-package)
    base="${1:?BASE commit required}"
    head="${2:?HEAD commit required}"
    target_dir="$(resolve_task_dir)"
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
    target_dir="$(resolve_task_dir)"
    rm -rf "$target_dir"
    rm -f "$ANCHOR"
    echo "Cleared: $target_dir"
    ;;

  ""|-h|--help|help)
    cat << 'EOF'
sprint-plan.sh — Structured PLAN.md + task-brief manager (.sprint/<task>/ per-task dirs)

Commands:
  init [name]                   Create/reuse .sprint/<name>/, write anchor, print path
                                (no name → timestamped sprint-<YYYYmmdd-HHMMSS>)
  path                          Print active task dir
  list                          List task dirs (marks active)
  write-plan                    Read PLAN.md from stdin → task dir
  show-plan                     Print PLAN.md path
  tasks                         List tasks with brief/report status
  task-brief <N>                Extract Task N → task-N-brief.md, print path
  task-report <N>               Print task-N-report.md path (touch if missing)
  review-package <BASE> <HEAD>  Write git diff → review-<..>.md, print path
  clear                         rm -rf active task dir + anchor

Layout:
  .sprint/<task>/   per-task: PLAN.md, briefs, reports, review packages
  .sprint/ root     cross-sprint: KNOWLEDGE.md, FINDINGS.md, CODE_MAP.md

Anchor:
  .sprint/CURRENT names the active task. Sibling commands (including
  sprint-checkpoint) read it back, so the path survives cd shifts and
  context compaction. Re-running init with an existing name resumes that
  task with all its state intact.
EOF
    ;;

  *)
    echo "Unknown command: $cmd" >&2
    echo "Run 'sprint-plan help' for usage." >&2
    exit 1
    ;;
esac
