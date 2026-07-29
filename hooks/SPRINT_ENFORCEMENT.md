# Sprint Enforcement — Path B

Cross-hook state machine that forces Complex work through `/keep:sprint`.
Upgrades `plan-mode-guard.sh`'s soft stderr advice into a hard Edit/Write
precondition.

## Why this exists

`plan-mode-guard.sh` blocks `EnterPlanMode` and prints a stderr reroute
advisory. But stderr advisories are prompt-level — model can rationalize
past them ("I'll just plan manually, no need for sprint skill"). This is
the exact failure mode this system is meant to prevent.

Path B closes the loophole: even if model rationalizes past the advisory,
the Edit/Write gate stays closed until `/keep:sprint` actually runs and
completes successfully.

## Flow

```
UserPromptSubmit ──▶ sprint-classify.sh
                       │
                       ├─ Not-Complex / Ambiguous → no-op
                       └─ Complex (verb + scope) ──▶ write pending state
                                                       │
Model turn ────────────────────────────────────────────┤
                                                       │
                                                       ▼
                       ┌─── sprint-clear.sh ◀── Skill(/keep:sprint) succeeds
                       │     (PostToolUse:Skill)        │
                       │                               │
                       ├─── pending preserved ◀── Skill failed or wrong name
                       │
                       ▼
PreToolUse:Edit|Write ──▶ sprint-gate.sh
                            │
                            ├─ no pending → allow
                            ├─ empty file_path → allow (degraded)
                            ├─ file whitelisted → allow
                            └─ pending + non-whitelisted → DENY (exit 2)

SessionEnd ──▶ sprint-session-stop.sh ──▶ clear pending for this session
```

## Hooks (4 source files + 1 lib)

| File | Event | Purpose |
|------|-------|---------|
| `hooks/lib/sprint-state.sh` | (sourced lib) | Atomic state protocol: set/clear/is_pending/get_reason |
| `hooks/sprint-classify.sh` | `UserPromptSubmit` | Classify prompt; write pending on Complex |
| `hooks/sprint-clear.sh` | `PostToolUse:Skill` | Clear pending on successful sprint skill |
| `hooks/sprint-gate.sh` | `PreToolUse:Edit\|Write\|MultiEdit` | Hard gate with whitelist |
| `hooks/sprint-session-stop.sh` | `SessionEnd` | Deterministic cleanup (TTL is fallback) |

State file: `.keep/state/sprint-pending-<sanitized-sid>.json` (per-session isolation, atomic write, 1800s TTL).

## Classification rules (sprint-classify.sh)

Conservative bias: **only set pending on unambiguous Complex signals**.

### Override (prefix only — actively clears existing pending)

User can suppress enforcement by starting the prompt with:

- `--no-sprint ...` — bypass for this turn + clear existing pending
- `trivial: ...` — declare trivial
- `standard: ...` — declare standard scope

### Negation keywords (substring, context-filtered)

If prompt contains (word-boundary match, after stripping "not X" / "non-X"):

`trivial`, `simple`, `quick`, `one-liner`, `one-line`

→ no pending written, but **existing pending preserved** (keyword negation
doesn't clear — too easy to false-positive on prompts like "this is not
trivial").

### Complex signal (both required)

- **Verb keyword**: `build`, `implement`, `refactor`, `ship`, `rewrite`, `migrate`, or phrase `add feature`
- **Scope hint**: ≥3 distinct file paths (regex requires `/` to avoid URL
  false positives) OR explicit quantifier (`several`, `multiple`, `all the`, `3+`, `three or more`)

If neither override nor Complex → Ambiguous, no-op.

## Override manual

| Intent | How |
|--------|-----|
| Bypass for one task | Start prompt with `--no-sprint` |
| Declare scope explicitly | Start prompt with `trivial:` or `standard:` |
| Disable globally for this session | Set env `SPRINT_ENFORCE=0` (also accepts `false`, `no`, `off`) |
| Disable across all projects | Remove the `.claude/settings.json` hook registration |

**Note**: keyword negations (`trivial`, `simple`, ...) appearing mid-prompt
do **not** clear existing pending — only suppress new pending writes. Use
explicit prefix override to clear.

## Whitelist (sprint-gate.sh)

Even with pending active, these paths are editable:

- `*.md` — any markdown file anywhere (docs, rules, plans)
- Paths whose **first repo-relative segment** is `rules/`, `docs/`, `.sprint/`, `.keep/`, or `tests/`

Repo-relative path is computed by stripping `$CLAUDE_PROJECT_DIR` prefix from
absolute paths. This anchoring prevents bypass via paths like `src/docs/x.py`
or `vendor/tests/payload.py` — only top-level `docs/x.py` is whitelisted.

**Accepted tradeoff**: `rules/` is whitelisted because rules are
documentation-like. A model could *theoretically* edit `rules/core.md` to
remove the enforcement policy, bypassing the gate. This is a residual
risk; mitigations are (a) rules edits are visible in PR review, (b)
documented here so reviewers know to watch for it.

## Troubleshooting

### "Gate blocked my edit but my task really is trivial"

- Prefix next prompt with `--no-sprint` or `trivial:`
- Or run `/keep:sprint` to genuinely clear the gate
- Or set `SPRINT_ENFORCE=0` for the session

### "Gate didn't block but I wanted it to"

The classifier is conservative — false negatives are expected on ambiguous
prompts. If you see a prompt that should have triggered but didn't, the
classifier either (a) didn't match a verb keyword, or (b) didn't match a
scope hint. Manually invoke `/keep:sprint`.

### "Pending file stuck in `.keep/state/`"

Three cleanup paths: (1) SessionEnd hook on session exit, (2) TTL 30min
expiry on next is_pending check, (3) next `--no-sprint` override.
Manual: `rm .keep/state/sprint-pending-*.json`.

### "Edit denied even after `/keep:sprint` ran"

Check sprint-clear logic: pending is only cleared if `tool_response.success`
is not `false` AND no error field. If skill exited with error (missing skill
file, parse error), pending is intentionally preserved — retry the skill or
use `--no-sprint`.

## Testing

All test files are pure-bash (no `bats` dependency):

```
tests/hooks/
├── test-sprint-state.sh           (7 cases)
├── test-sprint-classify.sh        (15 cases)
├── test-sprint-clear.sh           (9 cases)
├── test-sprint-gate.sh            (15 cases)
├── test-sprint-session-stop.sh    (4 cases)
└── integration-sprint-enforcement.sh  (9 scenarios)
```

Run all: `for t in tests/hooks/*.sh; do bash "$t"; done`

Total: **59 test cases**.

## Known limitations / future work

1. **bats / shellcheck not in CI** — pure-bash tests cover behavior, no static analysis safety net yet.
2. **No logging** — gate denials not logged; can't tune classifier false-positive rate from data.
3. **Whitelist is repo-wide** — can't selectively gate `src/` differently from `scripts/`.
4. **No skill-aware clearing for non-Skill entrypoints** — calling `/keep:sprint` via
   sub-agent dispatch (Agent tool with sprint-like prompt) does not clear
   pending because the Skill tool isn't invoked. Workaround: call the Skill directly.
5. **Project-scoped only** — activation requires `.claude/settings.json` in
   the project tree. Global activation (across all projects) would require
   user-level `~/.claude/settings.json` registration with appropriate cwd matching.

## Design history

See `.sprint/FINDINGS.md` (2026-07-28 entry) for the full plan-review and
code-review findings that shaped this implementation. Notable:
- PreToolUse:Skill → PostToolUse:Skill (prevented "skill failed but gate open")
- `${var//pat/}` apostrophe bug workaround
- jq `//` operator treats `false` as falsy (use `== false` instead)
- Override-clears-pending (integration test discovery)
