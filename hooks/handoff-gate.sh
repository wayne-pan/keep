#!/usr/bin/env bash
# handoff-gate.sh — PreCompact gate: no compact without a fresh handoff doc.
# Blocks (exit 2) when no keep-handoff-*.md in $TMPDIR is younger than
# GATE_FRESH_MIN minutes. Ordering contract: handoff ALWAYS precedes compact.
#
# Behaviour per path:
#   manual /compact → stderr below is shown to the user, no compact runs.
#   auto (proactive) → CC skips compaction, conversation continues; the
#     UserPromptSubmit early-warning hook (handoff-early-warning.sh) drives
#     the agent to write the handoff, then the next compact attempt passes.
#   auto (recovery from hard context-limit error) → request fails. The
#     early warning at 85% of the compact limit makes this path unreachable
#     in practice: the handoff doc lands turns before the limit.
#
# Fail-open: if the freshness scan itself errors, allow compaction —
# a broken gate must never deadlock the session (harness discipline).

set -euo pipefail

GATE_FRESH_MIN=60

# Drain stdin (CC pipes the event JSON; we don't need it — both triggers
# get the same gate).
cat >/dev/null

TMP="${TMPDIR:-/tmp}"

FRESH=$(python3 - "$TMP" "$GATE_FRESH_MIN" << 'PYEOF'
import sys, os, time, pathlib

tmp, fresh_min = sys.argv[1], int(sys.argv[2])
now = time.time()
best = None
for p in pathlib.Path(tmp).glob("keep-handoff-*.md"):
    if p.is_symlink():          # symlink = pre-create attack; ignore
        continue
    try:
        st = p.stat()
    except OSError:
        continue
    if st.st_uid != os.getuid():   # planted by another uid; ignore
        continue
    age = now - st.st_mtime
    if best is None or age < best:
        best = age
print("1" if best is not None and best <= fresh_min * 60 else "0")
PYEOF
) || FRESH=1

[ "$FRESH" = "1" ] && exit 0

echo "handoff-gate: no keep-handoff-*.md in $TMP fresher than ${GATE_FRESH_MIN}min." >&2
echo "Run /keep:handoff first (writes the pre-compact snapshot), then compact again." >&2
exit 2
