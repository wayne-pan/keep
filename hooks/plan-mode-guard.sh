#!/usr/bin/env bash
# plan-mode-guard.sh — PreToolUse hook: hard-block built-in plan mode, force reroute.
# Soft (exit 0) nudge was insufficient — Claude rationalized past stderr advisories.
# Hard block (exit 2) matches protect-files.sh / pr-gate.sh. To disable, edit settings.json.

set -uo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')

[ "$TOOL" = "EnterPlanMode" ] || exit 0

cat >&2 <<'EOF'
[plan-mode-guard] Built-in plan mode is blocked per rules/core.md.

Re-route based on task scope:
  - Complex feature/refactor (3+ files OR design OR >50 lines) → /keep:sprint
  - Complex bug/regression                                   → /keep:diagnosing-bugs
  - Standard (1-2 files, <50 lines)                          → skip plan, READ→BUILD→VERIFY
  - Trivial                                                  → skip plan, BUILD→VERIFY

To disable this gate, remove the EnterPlanMode matcher in settings.json.
EOF

exit 2
