#!/usr/bin/env bash
# post-compact-bridge.sh — PostCompact: point the freshly-compacted context
# at the newest handoff doc so dropped details are recoverable. The doc was
# written pre-compact (handoff-gate/early-warning pipeline); compaction is
# lossy, the doc is not.
#
# Advisory only. Docs older than STALE_MIN are not re-injected (that handoff
# belongs to a previous compact cycle).

set -euo pipefail

STALE_MIN=120

cat >/dev/null   # drain event JSON (unused)

TMP="${TMPDIR:-/tmp}"

DOC=$(python3 - "$TMP" "$STALE_MIN" << 'PYEOF'
import sys, os, time, pathlib

tmp, stale_min = sys.argv[1], int(sys.argv[2])
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
    if age > stale_min * 60:
        continue
    if best is None or age < best[0]:
        best = (age, str(p))
print(best[1] if best else "")
PYEOF
) || DOC=""

[ -n "$DOC" ] || exit 0

jq -n --arg doc "$DOC" '{
  "hookSpecificOutput": {
    "hookEventName": "PostCompact",
    "additionalContext": ("Compaction just ran. A pre-compact handoff snapshot exists at " + $doc + ". If you notice missing context (file state, decisions, identifiers), read it with the Read tool. It is one-shot: rm it after consuming — unless this session will hand off to another machine/agent later.")
  }
}'

exit 0
