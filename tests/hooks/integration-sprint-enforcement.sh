#!/usr/bin/env bash
# Integration tests for sprint-enforcement: end-to-end multi-hook flows.
# Simulates realistic sequences: classify → edit gate → skill clear → edit retry.
#
# Each scenario exercises multiple hooks in sequence against shared state.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOKS="$REPO_ROOT/hooks"
LIB_PATH="$HOOKS/lib/sprint-state.sh"

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

# Helper: invoke a hook with given JSON stdin, return its exit code
classify() {
  local json="$1"
  printf '%s' "$json" | bash "$HOOKS/sprint-classify.sh"
}

gate() {
  local json="$1"
  printf '%s' "$json" | bash "$HOOKS/sprint-gate.sh"
}

clearer() {
  local json="$1"
  printf '%s' "$json" | bash "$HOOKS/sprint-clear.sh"
}

# --- Scenario 1: Complex → Edit non-whitelisted → DENIED ---
test_complex_edit_denied() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"

  classify '{"prompt":"implement refactor across src/main.py src/util.py src/api.py","session_id":"s1","cwd":"/tmp"}' >/dev/null 2>&1
  gate '{"tool_name":"Edit","session_id":"s1","tool_input":{"file_path":"src/main.py"}}' >/dev/null 2>&1
  local gate_rc=$?
  rm -rf "$tmp"
  [ "$gate_rc" = "2" ] && return 0 || return 1
}

# --- Scenario 2: Complex → --no-sprint next prompt → Edit → ALLOWED ---
test_override_bypasses() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"

  # First prompt sets pending
  classify '{"prompt":"implement refactor across src/main.py src/util.py src/api.py","session_id":"s2","cwd":"/tmp"}' >/dev/null 2>&1
  # Second prompt with explicit override — must CLEAR existing pending
  classify '{"prompt":"--no-sprint now proceed","session_id":"s2","cwd":"/tmp"}' >/dev/null 2>&1
  gate '{"tool_name":"Edit","session_id":"s2","tool_input":{"file_path":"src/main.py"}}' >/dev/null 2>&1
  local gate_rc=$?
  rm -rf "$tmp"
  # Expected: ALLOWED (override cleared existing pending)
  [ "$gate_rc" = "0" ] && return 0 || return 1
}

# --- Scenario 3: Complex → Edit README.md → ALLOWED (whitelist) ---
test_complex_edit_md_allowed() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"

  classify '{"prompt":"implement refactor across src/main.py src/util.py src/api.py","session_id":"s3","cwd":"/tmp"}' >/dev/null 2>&1
  gate '{"tool_name":"Edit","session_id":"s3","tool_input":{"file_path":"README.md"}}' >/dev/null 2>&1
  local gate_rc=$?
  rm -rf "$tmp"
  [ "$gate_rc" = "0" ] && return 0 || return 1
}

# --- Scenario 4: Complex → TTL expire → Edit → ALLOWED ---
test_ttl_expire_allows() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  # shellcheck disable=SC1090
  source "$LIB_PATH"

  sprint_state_set s4 "ttl-test"
  local file="$tmp/sprint-pending-s4.json"
  jq '.expires_at_epoch = (.set_at_epoch - 100)' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

  gate '{"tool_name":"Edit","session_id":"s4","tool_input":{"file_path":"src/main.py"}}' >/dev/null 2>&1
  local gate_rc=$?
  rm -rf "$tmp"
  [ "$gate_rc" = "0" ] && return 0 || return 1
}

# --- Scenario 5: Session A pending, session B Edit → ALLOWED (isolation) ---
test_session_isolation() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"

  # Session A gets pending
  classify '{"prompt":"implement refactor across src/main.py src/util.py src/api.py","session_id":"sess-A","cwd":"/tmp"}' >/dev/null 2>&1
  # Session B tries to edit — must not be affected
  gate '{"tool_name":"Edit","session_id":"sess-B","tool_input":{"file_path":"src/main.py"}}' >/dev/null 2>&1
  local gate_rc=$?
  rm -rf "$tmp"
  [ "$gate_rc" = "0" ] && return 0 || return 1
}

# --- Scenario 6: Complex → Skill sprint succeeds → Edit → ALLOWED (happy path) ---
test_happy_path_sprint_clears() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"

  classify '{"prompt":"implement refactor across src/main.py src/util.py src/api.py","session_id":"s6","cwd":"/tmp"}' >/dev/null 2>&1
  clearer '{"tool_name":"Skill","session_id":"s6","tool_input":{"skill":"sprint"},"tool_response":{"success":true}}' >/dev/null 2>&1
  gate '{"tool_name":"Edit","session_id":"s6","tool_input":{"file_path":"src/main.py"}}' >/dev/null 2>&1
  local gate_rc=$?
  rm -rf "$tmp"
  [ "$gate_rc" = "0" ] && return 0 || return 1
}

# --- Scenario 7: Complex → Skill sprint FAILS → Edit → DENIED (pending preserved) ---
test_failed_skill_preserves_pending() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"

  classify '{"prompt":"implement refactor across src/main.py src/util.py src/api.py","session_id":"s7","cwd":"/tmp"}' >/dev/null 2>&1
  clearer '{"tool_name":"Skill","session_id":"s7","tool_input":{"skill":"sprint"},"tool_response":{"success":false}}' >/dev/null 2>&1
  gate '{"tool_name":"Edit","session_id":"s7","tool_input":{"file_path":"src/main.py"}}' >/dev/null 2>&1
  local gate_rc=$?
  rm -rf "$tmp"
  [ "$gate_rc" = "2" ] && return 0 || return 1
}

# --- Scenario 8: Complex → non-matching skill (review) → Edit → DENIED ---
test_non_matching_skill_preserves() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"

  classify '{"prompt":"implement refactor across src/main.py src/util.py src/api.py","session_id":"s8","cwd":"/tmp"}' >/dev/null 2>&1
  clearer '{"tool_name":"Skill","session_id":"s8","tool_input":{"skill":"review"},"tool_response":{"success":true}}' >/dev/null 2>&1
  gate '{"tool_name":"Edit","session_id":"s8","tool_input":{"file_path":"src/main.py"}}' >/dev/null 2>&1
  local gate_rc=$?
  rm -rf "$tmp"
  [ "$gate_rc" = "2" ] && return 0 || return 1
}

# --- Scenario 9: SPRINT_ENFORCE=0 disables everything end-to-end ---
test_env_escape_hatch_e2e() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  export SPRINT_ENFORCE=0

  classify '{"prompt":"implement refactor across src/main.py src/util.py src/api.py","session_id":"s9","cwd":"/tmp"}' >/dev/null 2>&1
  gate '{"tool_name":"Edit","session_id":"s9","tool_input":{"file_path":"src/main.py"}}' >/dev/null 2>&1
  local gate_rc=$?
  unset SPRINT_ENFORCE
  rm -rf "$tmp"
  [ "$gate_rc" = "0" ] && return 0 || return 1
}

# --- Runner ---

run "S1: Complex + Edit src/: denied"                        test_complex_edit_denied
run "S2: --no-sprint on 2nd prompt: override clears pending" test_override_bypasses
run "S3: Complex + Edit README.md: allowed (whitelist)"      test_complex_edit_md_allowed
run "S4: Complex + TTL expire: allowed"                      test_ttl_expire_allows
run "S5: Two-session isolation: B's edit allowed"            test_session_isolation
run "S6: Happy path: sprint skill clears, edit allowed"      test_happy_path_sprint_clears
run "S7: Failed skill preserves pending: edit denied"        test_failed_skill_preserves_pending
run "S8: Non-matching skill (review): pending preserved"     test_non_matching_skill_preserves
run "S9: SPRINT_ENFORCE=0 disables end-to-end"               test_env_escape_hatch_e2e

echo "---"
echo "Passed: $PASS_COUNT, Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
