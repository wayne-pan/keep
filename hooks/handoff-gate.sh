#!/usr/bin/env bash
# handoff-gate.sh — PreCompact gate: guarantee a pre-compact snapshot, never
# block the compact. A keep-handoff-*.md younger than GATE_FRESH_MIN passes
# straight through; overflow yields as below; otherwise the gate writes a
# mechanical auto-snapshot itself (git state + transcript pointer) and yields.
# Ordering contract: a snapshot ALWAYS precedes compact.
#
# Why auto-snapshot instead of exit 2: the hook cannot summon a model turn to
# run keep:handoff, and the model cannot invoke /compact — a block can never
# self-chain into "handoff then compact", it only dead-ends the user (e.g.
# compacting a fresh session: the 80% early warning never fired, nothing to
# hand off, yet the gate refused). Model-written handoffs remain the quality
# path (handoff-early-warning.sh + handoff-enforce.sh drive them at 80%);
# this gate is the automatic floor. post-compact-bridge.sh then points the
# compacted context at whatever doc exists — auto or model-written alike.
#
# Path resolution MUST stay identical to skills/handoff/SKILL.md (the writer):
# pinned per-user dir via KEEP_HANDOFF_DIR, defaulting under $HOME. Never
# $TMPDIR — it can differ between the Bash-tool shell (writer) and the hook
# process (checker) on macOS, splitting write/read paths (Linux hid this by
# both sides falling back to /tmp).
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

# --- Auto-snapshot fallback (was: exit 2 dead-end) ---
# No fresh doc, no overflow: write the mechanical snapshot, then yield.
SNAP="$TMP/keep-handoff-auto-$(date +%Y%m%d-%H%M%S)-$$.md"
# tr: a transcript_path carrying newlines must not smuggle extra markdown
# lines into the snapshot (event JSON is CC-owned, hardening only).
TRANSCRIPT=$({ printf '%s' "$EVENT_JSON" | python3 -c \
  'import json,sys; print(json.load(sys.stdin).get("transcript_path") or "(unavailable)")' \
  2>/dev/null || echo "(unavailable)"; } | tr -d '\n\r')
REPO_TOP=$(git rev-parse --show-toplevel 2>/dev/null || true)
(
  umask 077
  # Fresh machine: the handoff dir may not exist yet (only the skill writer
  # creates it) — without this the snapshot silently fails on first compact.
  mkdir -p "$TMP" 2>/dev/null || true
  {
    echo "# Handoff (auto snapshot — gate fallback, not a model summary)"
    echo
    echo "_Written by handoff-gate.sh at PreCompact, $(date '+%Y-%m-%d %H:%M:%S'):_"
    echo "_no model-written handoff fresher than ${GATE_FRESH_MIN}min existed._"
    echo "_Mechanical state only — mine the transcript for the full conversation._"
    echo
    echo "- Transcript (pre-compact conversation, JSONL): $TRANSCRIPT"
    if [ -n "$REPO_TOP" ]; then
      BRANCH=$(git -C "$REPO_TOP" branch --show-current 2>/dev/null || echo '(detached)')
      HEAD_SHA=$(git -C "$REPO_TOP" rev-parse --short HEAD 2>/dev/null || echo '?')
      echo "- Repo: $REPO_TOP @ $BRANCH (HEAD: $HEAD_SHA)"
      echo "- git status --short:"
      git -C "$REPO_TOP" status --short 2>/dev/null | sed 's/^/    /' || true
      echo "- git diff --stat:"
      git -C "$REPO_TOP" diff --stat 2>/dev/null | sed 's/^/    /' || true
      echo "- Recent commits:"
      git -C "$REPO_TOP" log --oneline -5 2>/dev/null | sed 's/^/    /' || true
    else
      echo "- Repo: not a git worktree (cwd: $PWD)"
    fi
    echo
    echo "One-shot: consuming session should rm this file after reading."
  } > "$SNAP"
) 2>/dev/null || true

if [ -s "$SNAP" ]; then
  echo "handoff-gate: no fresh handoff — auto-snapshot written: $SNAP" >&2
  echo "Compact proceeding. Post-compact: read the snapshot (and transcript)" >&2
  echo "if context went missing." >&2
else
  echo "handoff-gate: no fresh handoff AND auto-snapshot write failed — yielding" >&2
  echo "anyway (fail-open: an unwritable handoff dir must not deadlock compact)." >&2
fi
exit 0
