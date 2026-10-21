#!/usr/bin/env bash
# handoff-enforce.sh — PreToolUse(Bash): the teeth behind the early warning.
# When context usage is >= WARN_PCT of the compact window and no fresh
# keep-handoff-*.md exists, deny non-essential Bash calls (exit 2) with a
# directive to run keep:handoff NOW.
#
# Why: the early warning (UserPromptSubmit, handoff-early-warning.sh) is
# advisory and only fires at prompt boundaries — long agentic turns blew
# straight past it to the hard context limit ("context limit reached
# /compact or /clear"). This gate makes "handoff at 80%" actually happen:
# the very next non-essential tool call past the threshold is refused until
# the handoff doc is written.
#
# Anti-deadlock by construction:
#   - read-only gathering (git status/log/diff/show, ls, pwd) always passes
#   - any command mentioning keep-handoff passes (the doc write itself and
#     handoff-gate.sh's documented emergency-touch escape)
#   - Write/Edit tools are not matched — the doc can always be written
#   - user escapes need no Bash: /compact, /clear, /keep:handoff
#   - fail-open on any scan error — a gate must never paralyze the session
#
# Usage estimate + freshness check mirror handoff-early-warning.sh.

set -euo pipefail

WARN_PCT=80        # % of compact window where enforcement starts
DOC_FRESH_MIN=60   # handoff doc younger than this counts as "done" (==
                   # GATE_FRESH_MIN — long mid-band dwells must not re-block
                   # a session that already handed off; the doc still
                   # describes the task until auto-compact resets usage)

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
TP=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' || exit 0)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' || exit 0)
[ -n "$TP" ] && [ -f "$TP" ] || exit 0

# Handoff dir — same pinned resolution as handoff-gate.sh / SKILL.md writer.
TMP="${KEEP_HANDOFF_DIR:-${HOME:-/tmp}/.claude/handoffs}"

# Cheap allowlist BEFORE the (pricier) transcript scan. Best-effort, not a
# security boundary — safety-guard.sh owns that role.
if printf '%s' "$CMD" | grep -qiE 'handoff|\bgit (status|log|diff|show)\b|^ls( |$)|^pwd$'; then
    exit 0
fi

python3 - "$TP" "$TMP" "$WARN_PCT" "$DOC_FRESH_MIN" << 'PYEOF'
import sys, os, json, time, pathlib

tp, tmp, warn_pct, doc_fresh_min = (
    sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
)

# Compact window — statusline formula + the model cap CC actually enforces:
# effectiveWindow = min(env, model window). glm-5.3 resolves to 300k on CC
# 2.1.293 (verified via --debug-to-stderr: env=320k and env=2M both give
# effectiveWindow=300000), so a window above the cap only inflates this
# threshold past the real auto-compact point (~92% of 300k) and the
# gate never fires before the compact does. Env unset (the default —
# no settings.json entry) means the model-native window: the cap IS
# the limit. Env remains a shrink-only knob below the cap.
MODEL_WINDOW_CAP = 300_000

def compact_limit():
    if os.environ.get("DISABLE_AUTO_COMPACT"):
        return None               # auto-compact off -> nothing to enforce
    window_s = os.environ.get("CLAUDE_CODE_AUTO_COMPACT_WINDOW")
    window = int(window_s) if window_s and window_s.isdigit() else None
    if not window:
        return MODEL_WINDOW_CAP   # env unset -> model-native window
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
        sys.exit(0)               # fresh doc — gate open

print(
    f"context at ~{used // 1000}k/{limit // 1000}k tokens "
    f"({used * 100 // limit}% of compact window) with no fresh handoff doc. "
    "Non-essential Bash is denied until the handoff is written. Invoke the "
    "keep:handoff skill NOW via the Skill tool, then resume the interrupted "
    "task — native auto-compact fires on its own; no user action needed.",
    file=sys.stderr,
)
sys.exit(2)
PYEOF

exit $?
