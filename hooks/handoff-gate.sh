#!/usr/bin/env bash
# handoff-gate.sh — PreCompact gate: no compact without a fresh handoff doc.
# Blocks (exit 2) when no keep-handoff-*.md in the handoff dir is younger than
# GATE_FRESH_MIN minutes. Ordering contract: handoff ALWAYS precedes compact.
#
# Path resolution MUST stay identical to skills/handoff/SKILL.md (the writer):
# pinned per-user dir via KEEP_HANDOFF_DIR, defaulting under $HOME. Never
# $TMPDIR — it can differ between the Bash-tool shell (writer) and the hook
# process (checker) on macOS, splitting write/read paths (Linux hid this by
# both sides falling back to /tmp).
#
# Behaviour per path:
#   manual /compact → stderr below is shown to the user, no compact runs.
#   auto (proactive) → CC skips compaction, conversation continues; the
#     UserPromptSubmit early-warning hook (handoff-early-warning.sh) drives
#     the agent to write the handoff, then the next compact attempt passes.
#   auto (recovery from hard context-limit error) → overflow escape below.
#
# OVERFLOW ESCAPE — when the model's REAL context limit is below the
# configured window (CLAUDE_CODE_AUTO_COMPACT_WINDOW=320000 driving a 200k
# model, say), the early warning at 80% of the compact limit never fires:
# the model hard-errors first. No room is left to run keep:handoff, so
# blocking the recovery compact deadlocks the session. Therefore: if the
# transcript tail shows a context-limit API error after the last successful
# assistant turn, the gate yields (exit 0 + stderr note). mem-precompact.sh
# still emergency-saves; post-compact-bridge.sh points at the newest doc if
# one exists. A gate must never paralyze the session (harness discipline).
#
# Manual escape hatch (needs no model turns) if the overflow scan misses:
#   touch "$TMP/keep-handoff-emergency.md"   # then compact again
#
# Fail-open: if the freshness scan itself errors, allow compaction —
# a broken gate must never deadlock the session (harness discipline).

set -euo pipefail

GATE_FRESH_MIN=60

# Event JSON from CC carries transcript_path. Handed to python via env:
# the heredoc below already owns stdin.
EVENT_JSON=$(cat)

TMP="${KEEP_HANDOFF_DIR:-${HOME:-/tmp}/.claude/handoffs}"

VERDICT=$(EVENT_JSON="$EVENT_JSON" python3 - "$TMP" "$GATE_FRESH_MIN" << 'PYEOF'
import sys, os, json, time, pathlib

tmp, fresh_min = sys.argv[1], int(sys.argv[2])
now = time.time()

# --- Freshness: newest keep-handoff-*.md owned by us, not a symlink
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
if best is not None and best <= fresh_min * 60:
    print("fresh")
    sys.exit(0)

# --- Overflow: context-limit API error after the last successful turn?
# Wording varies by provider (Anthropic "prompt is too long ... maximum",
# OpenAI-style "maximum context length", CN proxies "上下文") — substring
# match on the raw line keeps it provider-agnostic.
try:
    tp = json.loads(os.environ.get("EVENT_JSON", "") or "{}").get("transcript_path")
except json.JSONDecodeError:
    tp = None
if tp and os.path.isfile(tp):
    OVERFLOW_PATTERNS = (
        "prompt is too long", "maximum context", "context length",
        "context window", "上下文",
    )
    try:
        with open(tp, "rb") as f:
            try:                  # seek ~200 lines back (statusline technique)
                f.seek(0, 2)
                size = f.tell()
                f.seek(max(0, size - 200 * 400))
                lines = f.read().decode("utf-8", "replace").splitlines()
            except OSError:
                lines = []
    except OSError:
        lines = []
    last_success = last_overflow = -1
    for i, line in enumerate(lines[-200:]):
        if '"usage"' not in line and '"isApiErrorMessage"' not in line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get("isApiErrorMessage"):
            if any(pat in line.lower() for pat in OVERFLOW_PATTERNS):
                last_overflow = i
        elif (obj.get("message") or {}).get("usage"):
            last_success = i
    if last_overflow > last_success:
        print("overflow")
        sys.exit(0)

print("block")
PYEOF
) || VERDICT=fresh

case "$VERDICT" in
  fresh) exit 0 ;;
  overflow)
    echo "handoff-gate: context-limit error with no fresh handoff — yielding" >&2
    echo "so the recovery compact can run (model limit below the configured" >&2
    echo "window; early warning never fired). mem-precompact.sh emergency-saves." >&2
    exit 0 ;;
esac

echo "handoff-gate: no keep-handoff-*.md in $TMP fresher than ${GATE_FRESH_MIN}min." >&2
echo "Run /keep:handoff first (writes the pre-compact snapshot), then compact again." >&2
echo "Context already exhausted so handoff can't run? Escape without model turns:" >&2
echo "  touch \"$TMP/keep-handoff-emergency.md\"   # then compact again" >&2
exit 2
