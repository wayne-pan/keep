#!/usr/bin/env bash
# handoff-early-warning.sh — UserPromptSubmit: as context approaches the
# auto-compact threshold, direct the agent to run keep:handoff NOW so a
# fresh handoff doc exists before compaction fires (handoff-gate.sh enforces
# the ordering; this hook is what drives the handoff to happen).
#
# Token estimate: transcript JSONL, last assistant message usage (approximates
# scripts/statusline.py — raw usage sum, no model-window clamp; docs warn the
# transcript may lag the in-memory conversation — fine for an early warning).
# Threshold mirrors statusline's get_compact_config():
#   limit = CLAUDE_CODE_AUTO_COMPACT_WINDOW (the only knob the CC binary
#   actually reads — CLAUDE_AUTOCOMPACT_PCT_OVERRIDE was never honored)
# so the statusline cap bar and this warning always agree. DISABLE_AUTO_COMPACT
# disables this warning too. Enforcement lives in handoff-enforce.sh.
#
# Re-nags every prompt while over threshold until a handoff doc fresher than
# DOC_FRESH_MIN exists (< GATE_FRESH_MIN, so a doc written on warning always
# passes the gate). Advisory only — never blocks.

set -euo pipefail

WARN_PCT=80        # % of compact limit where the warning starts
DOC_FRESH_MIN=30   # handoff doc younger than this counts as "done"

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
TP=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' || exit 0)
[ -n "$TP" ] && [ -f "$TP" ] || exit 0

# Handoff dir — same pinned resolution as handoff-gate.sh / SKILL.md writer.
# Never $TMPDIR: it drifts between Bash-tool shell and hook env on macOS.
TMP="${KEEP_HANDOFF_DIR:-${HOME:-/tmp}/.claude/handoffs}"

python3 - "$TP" "$TMP" "$WARN_PCT" "$DOC_FRESH_MIN" << 'PYEOF'
import sys, os, json, time, pathlib

tp, tmp, warn_pct, doc_fresh_min = (
    sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
)

def out(s):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": s,
        }
    }))

# Compact limit — statusline formula + the model cap CC actually enforces:
# effectiveWindow = min(env, model window). glm-5.3 resolves to 300k on CC
# 2.1.293 (verified via --debug-to-stderr: env=320k and env=2M both give
# effectiveWindow=300000), so a window above the cap only inflates this
# threshold past the real auto-compact point (~92% of 300k) and the
# warning never beats the compact.
MODEL_WINDOW_CAP = 300_000

def compact_limit():
    if os.environ.get("DISABLE_AUTO_COMPACT"):
        return None               # auto-compact off -> nothing to warn about
    window_s = os.environ.get("CLAUDE_CODE_AUTO_COMPACT_WINDOW")
    window = int(window_s) if window_s and window_s.isdigit() else None
    if not window:
        return 180_000
    return min(window, MODEL_WINDOW_CAP)

# Context estimate: last REAL assistant usage in the transcript tail
def context_tokens():
    try:
        with open(tp, "rb") as f:
            try:                  # seek ~2MB back, not 200*400B: post-compact
                                  # continuation lines embed the whole summary
                                  # and push the last usage line 100KB+ past
                                  # EOF (measured 114,383B on a 266k tail —
                                  # the 80KB window went blind after compacts)
                f.seek(0, 2)
                size = f.tell()
                f.seek(max(0, size - 2_000_000))
                lines = f.read().decode("utf-8", "replace").splitlines()
            except OSError:
                return None
    except OSError:
        return None
    for line in reversed(lines):
        if '"usage"' not in line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get("isApiErrorMessage"):
            continue              # synthetic error rows carry usage (all-zero)
        u = (obj.get("message") or {}).get("usage") or {}
        if not u:
            continue
        total = (u.get("input_tokens", 0)
                 + u.get("cache_read_input_tokens", 0)
                 + u.get("cache_creation_input_tokens", 0)
                 + u.get("output_tokens", 0))
        if total <= 0:
            continue              # zero-usage synthetic ("No response requested.")
        return total
    return None

limit = compact_limit()
if limit is None:
    sys.exit(0)
used = context_tokens()
if used is None or used < limit * warn_pct // 100:
    sys.exit(0)

# Fresh handoff doc? (symlinks / foreign-uid files ignored — pre-create attack)
now = time.time()
fresh = False
for p in pathlib.Path(tmp).glob("keep-handoff-*.md"):
    if p.is_symlink():
        continue
    try:
        st = p.stat()
    except OSError:
        continue
    if st.st_uid != os.getuid():
        continue
    if now - st.st_mtime <= doc_fresh_min * 60:
        fresh = True
        break
if fresh:
    sys.exit(0)

out(
    f"Context at ~{used // 1000}k/{limit // 1000}k tokens "
    f"({used * 100 // limit}% of compact limit). Before auto-compact fires: "
    "(1) invoke the keep:handoff skill NOW via the Skill tool to write the "
    "pre-compact snapshot; (2) once it completes, tell the user to run "
    "/compact. Without a fresh doc, handoff-gate.sh only manages a "
    "mechanical auto-snapshot — this handoff is the quality path."
)
PYEOF

exit 0
