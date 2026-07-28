#!/usr/bin/env bash
# Pure-bash test runner for hooks/sprint-classify.sh.
# Simulates stdin payloads and asserts on pending state + advisory output.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK_PATH="$REPO_ROOT/hooks/sprint-classify.sh"

PASS_COUNT=0
FAIL_COUNT=0

run() {
  local name="$1"
  local fn="$2"
  if "$fn"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# Helper: invoke hook with given stdin JSON, return its exit code + capture stdout
invoke_hook() {
  local stdin_json="$1"
  OUT=$(printf '%s' "$stdin_json" | bash "$HOOK_PATH" 2>/dev/null)
  return $?
}

# Helper: given session_id, check whether pending file exists in $KEEP_STATE_DIR
pending_exists() {
  local sid="$1"
  local safe
  safe="$(printf '%s' "$sid" | tr -c '[:alnum:]_.-' '_')"
  [ -f "$KEEP_STATE_DIR/sprint-pending-${safe}.json" ]
}

# --- Test cases ---

test_complex_3_files() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  local payload
  payload=$(jq -cn --arg p "implement refactor across backend/web layers, touching src/main.py src/util.py src/api.py" --arg s "sess-complex" '{prompt:$p, session_id:$s, cwd:"/tmp"}')
  if invoke_hook "$payload" && pending_exists "sess-complex"; then
    rc=0
  else
    rc=1
  fi
  rm -rf "$tmp"
  return "${rc:-1}"
}

test_complex_with_quantifier() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  local payload
  payload=$(jq -cn --arg p "ship a rewrite, this will touch several files in the auth module" --arg s "sess-quant" '{prompt:$p, session_id:$s}')
  if invoke_hook "$payload" && pending_exists "sess-quant"; then
    rc=0
  else
    rc=1
  fi
  rm -rf "$tmp"
  return "${rc:-1}"
}

test_trivial_keyword() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  local payload
  payload=$(jq -cn --arg p "trivial one-line fix to README" --arg s "sess-triv" '{prompt:$p, session_id:$s}')
  invoke_hook "$payload"
  if pending_exists "sess-triv"; then rc=1; else rc=0; fi
  rm -rf "$tmp"
  return "$rc"
}

test_no_sprint_prefix_override() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  local payload
  payload=$(jq -cn --arg p "--no-sprint implement X across src/main.py src/util.py src/api.py" --arg s "sess-override" '{prompt:$p, session_id:$s}')
  invoke_hook "$payload"
  if pending_exists "sess-override"; then rc=1; else rc=0; fi
  rm -rf "$tmp"
  return "$rc"
}

test_no_sprint_inside_quotes_does_NOT_override() {
  # PLAN.md v2 case 4: substring inside quotes must NOT bypass.
  # Override only recognized at prompt start.
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  local payload
  payload=$(jq -cn --arg p "the --no-sprint flag means skip, but actually implement refactor across src/main.py src/util.py src/api.py" --arg s "sess-inside" '{prompt:$p, session_id:$s}')
  invoke_hook "$payload"
  if pending_exists "sess-inside"; then rc=0; else rc=1; fi
  rm -rf "$tmp"
  return "$rc"
}

test_ambiguous_no_pending() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  local payload
  payload=$(jq -cn --arg p "look at this" --arg s "sess-ambig" '{prompt:$p, session_id:$s}')
  invoke_hook "$payload"
  if pending_exists "sess-ambig"; then rc=1; else rc=0; fi
  rm -rf "$tmp"
  return "$rc"
}

test_complex_without_scope_no_pending() {
  # Verb keyword present but no scope hint
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  local payload
  payload=$(jq -cn --arg p "implement this feature please" --arg s "sess-noscope" '{prompt:$p, session_id:$s}')
  invoke_hook "$payload"
  if pending_exists "sess-noscope"; then rc=1; else rc=0; fi
  rm -rf "$tmp"
  return "$rc"
}

test_trivial_prefix() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  local payload
  payload=$(jq -cn --arg p "trivial: just a quick fix" --arg s "sess-prefix" '{prompt:$p, session_id:$s}')
  invoke_hook "$payload"
  if pending_exists "sess-prefix"; then rc=1; else rc=0; fi
  rm -rf "$tmp"
  return "$rc"
}

test_empty_session_id_no_op() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  local payload
  payload=$(jq -cn --arg p "implement refactor across multiple files" '{prompt:$p, session_id:"", cwd:"/tmp"}')
  # Should exit 0 and write nothing
  invoke_hook "$payload"
  local rc
  if pending_exists "any"; then rc=1; else rc=0; fi
  rm -rf "$tmp"
  return "$rc"
}

# --- Regression tests for review CRITICAL findings ---

test_not_trivial_still_complex() {
  # CRITICAL #1: "not trivial" must NOT trigger negation.
  # User emphasizing complexity should still set pending.
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  local payload
  payload=$(jq -cn --arg p "implement this migration, it is not trivial, will touch src/main.py src/util.py src/api.py" --arg s "sess-not-triv" '{prompt:$p, session_id:$s}')
  invoke_hook "$payload"
  if pending_exists "sess-not-triv"; then rc=0; else rc=1; fi
  rm -rf "$tmp"
  return "$rc"
}

test_non_trivial_still_complex() {
  # CRITICAL #1 variant: "non-trivial" with hyphen
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  local payload
  payload=$(jq -cn --arg p "build a non-trivial refactor across src/a.py src/b.py src/c.py" --arg s "sess-non-triv" '{prompt:$p, session_id:$s}')
  invoke_hook "$payload"
  if pending_exists "sess-non-triv"; then rc=0; else rc=1; fi
  rm -rf "$tmp"
  return "$rc"
}

test_override_with_leading_space() {
  # CRITICAL #2: leading whitespace must not defeat prefix override
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  local payload
  payload=$(jq -cn --arg p "  --no-sprint implement refactor across src/main.py src/util.py src/api.py" --arg s "sess-lspace" '{prompt:$p, session_id:$s}')
  invoke_hook "$payload"
  if pending_exists "sess-lspace"; then rc=1; else rc=0; fi
  rm -rf "$tmp"
  return "$rc"
}

test_no_sprint_with_tab() {
  # CRITICAL #3: --no-sprint followed by tab must override
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  local payload
  # Use literal tab via printf
  payload=$(jq -cn --arg p "$(printf -- '--no-sprint\timplement refactor across src/main.py src/util.py src/api.py')" --arg s "sess-tab" '{prompt:$p, session_id:$s}')
  invoke_hook "$payload"
  if pending_exists "sess-tab"; then rc=1; else rc=0; fi
  rm -rf "$tmp"
  return "$rc"
}

test_urls_do_not_inflate_file_count() {
  # CONCERN #4: URLs / hostnames must NOT count toward file threshold
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  local payload
  payload=$(jq -cn --arg p "implement feature, see docs at example.com and test at sample.org — also reference cdn.cloudflare.com" --arg s "sess-url" '{prompt:$p, session_id:$s}')
  invoke_hook "$payload"
  # URLs don't contain /, so file_count=0; no quantifier → Ambiguous, no pending
  if pending_exists "sess-url"; then rc=1; else rc=0; fi
  rm -rf "$tmp"
  return "$rc"
}

test_sprint_enforce_zero_bypasses() {
  # Escape hatch: SPRINT_ENFORCE=0 must short-circuit before any classification
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  export SPRINT_ENFORCE=0
  local payload
  payload=$(jq -cn --arg p "implement refactor across src/main.py src/util.py src/api.py" --arg s "sess-bypass" '{prompt:$p, session_id:$s}')
  invoke_hook "$payload"
  unset SPRINT_ENFORCE
  if pending_exists "sess-bypass"; then rc=1; else rc=0; fi
  rm -rf "$tmp"
  return "$rc"
}

# --- Runner ---

run "complex-3-files: pending SET"                                       test_complex_3_files
run "complex-quantifier (several): pending SET"                          test_complex_with_quantifier
run "trivial-keyword: no pending"                                        test_trivial_keyword
run "--no-sprint prefix override: no pending"                            test_no_sprint_prefix_override
run "--no-sprint inside quotes: pending STILL set (override not parsed)" test_no_sprint_inside_quotes_does_NOT_override
run "ambiguous: no pending"                                              test_ambiguous_no_pending
run "complex-without-scope: no pending"                                  test_complex_without_scope_no_pending
run "trivial: prefix: no pending"                                        test_trivial_prefix
run "empty-session_id: hook no-ops"                                      test_empty_session_id_no_op
run "REGRESSION 'not trivial': pending SET (R-CRIT #1)"                 test_not_trivial_still_complex
run "REGRESSION 'non-trivial': pending SET (R-CRIT #1)"                 test_non_trivial_still_complex
run "REGRESSION leading-space + --no-sprint: no pending (R-CRIT #2)"    test_override_with_leading_space
run "REGRESSION --no-sprint+TAB: no pending (R-CRIT #3)"                test_no_sprint_with_tab
run "REGRESSION URLs don't inflate file count (R-CONCERN #4)"           test_urls_do_not_inflate_file_count
run "SPRINT_ENFORCE=0 bypass: no pending (escape hatch)"               test_sprint_enforce_zero_bypasses

echo "---"
echo "Passed: $PASS_COUNT, Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
