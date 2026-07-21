#!/usr/bin/env bash
# plan-mode-guard.sh — PreToolUse hook: nudge toward /keep:sprint or /keep:diagnosing-bugs
# Soft (exit 0): injects reminder via stderr, lets Claude decide. Non-blocking.
#
# Routes: EnterPlanMode → stderr classification reminder → Claude picks /keep:sprint
# (features/refactors) or /keep:diagnosing-bugs (bugs/regressions) for Complex work.
# Upgrade path: change `exit 0` to `exit 2` to hard-block (forces Claude to reroute).

set -uo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')

[ "$TOOL" = "EnterPlanMode" ] || exit 0

cat >&2 <<'EOF'
[plan-mode-guard] Before entering built-in plan mode, classify per rules/core.md:
- Complex feature/refactor (3+ files OR design OR >50 lines) → exit plan mode, run /keep:sprint
- Complex bug/regression → exit plan mode, run /keep:diagnosing-bugs
- Standard (1-2 files) → plan mode OK
EOF

exit 0
