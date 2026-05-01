#!/usr/bin/env bash
# pre-compact-instructions.sh — inject compaction priorities before context compression.
# Installed as PreCompact hook.
# Tells the summarizer what to preserve verbatim vs summarize.

set -euo pipefail

INSTRUCTIONS=$(cat << 'INSTR'
Compaction priorities (preserve in order — 1=highest, 11=first to drop):
1. Architecture decisions and rationale — preserve verbatim
2. Active task goals and current status — preserve verbatim
3. Error context and root causes — preserve verbatim
4. Pending items and blockers — preserve verbatim
5. Modified files list with line ranges — preserve verbatim
6. Identifiers (variable names, function signatures, class names) — preserve verbatim, never paraphrase
7. Code snippets under 10 lines — preserve verbatim if referenced in active work
8. Cache prefix discipline — preserve conversation prefix over recent tool output.
   Tool results can be re-obtained with one API call; cache misses cost 20x.
9. Exploration results — keep conclusions, drop raw search results
10. Tool output and logs — DROP entirely if >50 lines; summarize to key findings if shorter
11. File contents read via Read tool — DROP full content, keep only file:line references

Checkpoint: Before compacting, verify a session-checkpoint observation exists for current work.
If not, create one via remember() with current git state and modified files.
Preserve the checkpoint ID and branch name through compaction for session resume.
INSTR
)

jq -n --arg instr "$INSTRUCTIONS" '{
  "hookSpecificOutput": {
    "hookEventName": "PreCompact",
    "additionalContext": $instr
  }
}'

exit 0
