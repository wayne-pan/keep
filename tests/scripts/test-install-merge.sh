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
print("import re\n" + m.group(0))
m = re.search(r'def normalize_hooks\(s\):.*?\n\n', src, re.S)
if m:
    print(m.group(0))
PY
}

merge_ns() { python3 -c "
import sys
ns = {}
exec(sys.stdin.read(), ns)
import json
existing = json.loads(sys.argv[1])
if 'normalize_hooks' in ns:
    # normalize_hooks takes the WHOLE settings object, but this
    # harness feeds merge_hooks the hooks subtree — wrap it
    ns['normalize_hooks']({'hooks': existing})
print(json.dumps(ns['merge_hooks'](existing, json.loads(sys.argv[2]))))
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

t_dedup_cancel_append() {
  # regression: within-group dedup (-1) cancelling a default append (+1)
  # must not be skipped by an equal-length guard
  local out; out=$(extract | merge_ns \
    '{"Stop":[{"hooks":[{"command":"a.sh"},{"command":"a.sh"}]}]}' \
    '{"Stop":[{"hooks":[{"command":"a.sh"},{"command":"n.sh"}]}]}')
  [ "$(echo "$out" | jq -r '.Stop[0].hooks | map(.command) | join(",")')" = "a.sh,n.sh" ]
}
t_normalize_collapses_path_variants() {
  # /home/x, /Users/y, $HOME forms of one script + quoted variant + null
  # command must collapse to single $HOME entries without crashing
  local out; out=$(extract | merge_ns \
    '{"Stop":[{"hooks":[
        {"command":"/home/x/.claude/hooks/a.sh"},
        {"command":"/Users/y/.claude/hooks/a.sh"},
        {"command":"$HOME/.claude/hooks/a.sh"},
        {"command":"bash \u0027/home/z/.claude/hooks/h.sh\u0027 session"},
        {"command":null}]}]}' \
    '{"Stop":[{"hooks":[{"command":"$HOME/.claude/hooks/a.sh"}]}]}')
  local cmds; cmds=$(echo "$out" | jq -r '.Stop[0].hooks | map(.command) | join("|")')
  [ "$cmds" = '$HOME/.claude/hooks/a.sh|bash $HOME/.claude/hooks/h.sh session|' ] \
    || { echo "  got: $cmds"; return 1; }
}

run "multi-hook merge keeps all" t_multi_add
run "merge idempotent (dedup)" t_dedup_idempotent
run "no-matcher group appended" t_no_matcher_appends_group
run "malformed hook entry safe" t_missing_command_key_safe
run "dedup-cancel-append keeps default" t_dedup_cancel_append
run "normalize collapses path variants" t_normalize_collapses_path_variants
echo; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
