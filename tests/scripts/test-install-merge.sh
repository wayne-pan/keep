#!/usr/bin/env bash
# Pure-bash test for install.sh merge_hooks — blast-radius-critical merge logic.
# Extracts the function via regex and exercises multi-add, dedup, new-group.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL_SH="$REPO_ROOT/scripts/install.sh"

PASS=0; FAIL=0
run() { if "$2"; then echo "PASS: $1"; PASS=$((PASS+1)); else echo "FAIL: $1"; FAIL=$((FAIL+1)); fi; }

extract() {
  python3 - "$INSTALL_SH" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'def merge_hooks\(existing, defaults\):.*?\n    return result\n', src, re.S)
assert m, "merge_hooks not found"
print(m.group(0))
PY
}

merge_ns() { python3 -c "
import sys
ns = {}
exec(sys.stdin.read(), ns)
import json
print(json.dumps(ns['merge_hooks'](json.loads(sys.argv[1]), json.loads(sys.argv[2]))))
" "$1" "$2"; }

t_multi_add() {
  local out; out=$(extract | merge_ns \
    '{"Stop":[{"hooks":[{"command":"a.sh"},{"command":"b.sh"}]}]}' \
    '{"Stop":[{"hooks":[{"command":"a.sh"},{"command":"b.sh"},{"command":"m.sh"},{"command":"f.sh"}]}]}')
  [ "$(echo "$out" | jq -r '.Stop[0].hooks | map(.command) | join(",")')" = "a.sh,b.sh,m.sh,f.sh" ]
}
t_dedup_idempotent() {
  local d once twice
  d='{"Stop":[{"hooks":[{"command":"a.sh"},{"command":"b.sh"}]}]}'
  once=$(extract | merge_ns "$d" "$d")
  twice=$(extract | merge_ns "$once" "$d")
  [ "$(echo "$once" | jq -cS .)" = "$(echo "$twice" | jq -cS .)" ]
}
t_no_matcher_appends_group() {
  local out; out=$(extract | merge_ns \
    '{"PostToolUse":[{"matcher":"Bash","hooks":[{"command":"x.sh"}]}]}' \
    '{"PostToolUse":[{"hooks":[{"command":"s.sh"}]}]}')
  [ "$(echo "$out" | jq '.PostToolUse | length')" = "2" ] \
    && [ "$(echo "$out" | jq -r '.PostToolUse[1].hooks[0].command')" = "s.sh" ]
}
t_missing_command_key_safe() {
  local out; out=$(extract | merge_ns \
    '{"Stop":[{"hooks":[{"command":"a.sh"},{"type":"weird"}]}]}' \
    '{"Stop":[{"hooks":[{"command":"a.sh"},{"command":"n.sh"}]}]}')
  [ "$(echo "$out" | jq -r '.Stop[0].hooks | map(.command // "?") | join(",")')" = "a.sh,?,n.sh" ]
}

run "multi-hook merge keeps all" t_multi_add
run "merge idempotent (dedup)" t_dedup_idempotent
run "no-matcher group appended" t_no_matcher_appends_group
run "malformed hook entry safe" t_missing_command_key_safe
echo; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
