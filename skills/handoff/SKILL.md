---
name: keep:handoff
version: "1.0"
triggers: ["/keep:handoff", "/keep:pass off", "/keep:switch session", "/keep:continue elsewhere", "/keep:wrap up session"]
description: >
  Compact the current conversation into a handoff document so another agent (or a
  fresh session) can pick up the work without re-deriving context. TRIGGER when:
  user says "/keep:handoff", "pass this off", "wrap up the session", "I'm switching
  machines", when context is approaching the smart-zone ceiling and a fork is
  safer than a compact, or when the UserPromptSubmit early-warning hook directs
  a pre-compact snapshot (handoff-gate.sh auto-writes a mechanical fallback
  snapshot if none exists — a snapshot ALWAYS precedes compact). After
  writing, close by intent: fork intent (machine switch / new session) → end
  the turn, the doc is the baton; otherwise (hook-triggered or mid-task
  snapshot) → continue in-session — native auto-compact fires on its own,
  zero user action. Differs from
  /compact (continue in same session) and from session-checkpoint (which writes
  to memory for the resume protocol). Output goes to a pinned per-user dir —
  $HOME/.claude/handoffs, overridable via KEEP_HANDOFF_DIR (never the repo,
  never $TMPDIR: it drifts between the Bash shell and hook processes on macOS).
  Do NOT trigger for: end-of-task cleanup
  (use /keep:sprint Phase 8 Reflect), or when the work is fully shipped.
resources: ['mind', 'git-diff']
---

# Handoff

Write a handoff document that lets a fresh agent continue the work. The document is a **fork or a pre-compact snapshot**, depending on trigger: machine-switch fork — the new session reads it and runs, the old session is done; hook-triggered continuity — the same session resumes after auto-compact with this doc as its recovery net. This is different from `/compact` (which is a **continue** — same session, summarised) and from the resume protocol's session-checkpoint (which is **memory state** for the next session's `wakeup`).

## When to Choose Handoff vs Compact vs Checkpoint

| Tool | Relationship | When |
|------|-------------|------|
| **handoff** (this skill) | Fork — new session references a file; or pre-compact snapshot for the same session (hook-triggered) | Machine switch, different agent, detour through `/keep:prototype` and back; or hooks fired at the context ceiling mid-task |
| `/compact` | Continue — same session, compressed | Current session is hitting context limits but the work is one continuous thread |
| session-checkpoint | Memory state — next session's `wakeup()` reads it | End of session, expect to resume tomorrow; wants decisions + modified files in `mcp__mind` |

Handoff is for **cross-context bridges** — and, when the hooks trigger it, for pre-compact snapshots. If you can compact, compact (the hooks own the exception: when they fire, handoff IS the compact preparation). If you're done for the day, checkpoint. If you're handing the baton to a different runner, handoff.

## Workflow

### 1. Gather

- [ ] `git status --short` and `git diff --stat` — what's changed
- [ ] `git log --oneline -5` — recent commits for context
- [ ] `mcp__mind__search "session-checkpoint"` — pull the current checkpoint if one exists
- [ ] Identify the **task goal** in one sentence (what "done" looks like)
- [ ] Identify **completed work** (cite commits / file paths)
- [ ] Identify **in-flight work** (uncommitted changes, half-finished modules)
- [ ] Identify **next moves** (the immediate next 1-3 steps)

### 2. Detect available skills for the next session

Look at the next moves. For each, name the skill that should handle it:

```
Next move: "implement the cancellation policy module"
  → /keep:tdd (vertical slice red-green)

Next move: "decide between two interface shapes for the payment router"
  → /keep:design-interface

Next move: "debug why orders are double-charged"
  → /keep:diagnosing-bugs
```

These become the **Suggested skills** section — concrete handoffs, not "use your judgement".

### 3. Sanitise

Scrub the document for:

- API keys, tokens, passwords (replace with `<redacted: which credential>`)
- Personal email / PII (replace with `<redacted: person role>`)
- Internal URLs that the next agent can't reach (note as "internal-only: <purpose>")
- Customer data (replace with synthetic equivalents)

**Default to redacting anything you're unsure about.** A handoff is not the place to leak.

### 4. Write

Write to the **pinned handoff dir**, not the repo:

```bash
HANDOFF_DIR="${KEEP_HANDOFF_DIR:-$HOME/.claude/handoffs}"
mkdir -p "$HANDOFF_DIR"
HANDOFF="$HANDOFF_DIR/keep-handoff-$(date +%Y%m%d-%H%M%S).md"
# Create with restrictive permissions from the start (avoids TOCTOU window
# where default umask leaves the file world-readable between create and chmod).
(umask 077 && touch "$HANDOFF")
# Then write content to "$HANDOFF" — file is already 600
# Next session consumes it, then: rm "$HANDOFF"   # one-shot, do not leave secrets lying around
```

**Never** write handoffs inside the working repo, and **never via `$TMPDIR`** — the hooks that gate compaction (`handoff-gate.sh`, `handoff-early-warning.sh`, `post-compact-bridge.sh`) resolve this same pinned path; a `$TMPDIR` write can land in a different directory than the hooks scan on macOS (per-process `TMPDIR` drift), which deadlocks the compact gate. The dir lives under `$HOME` and is created `700`, files `600` — private even on shared systems. The file is **one-shot**: the consuming session must `rm` it after reading.

**Document structure:**

```md
# Handoff: <one-line task description>

_Generated: YYYY-MM-DD HH:MM_
_Repo: <path> @ <branch> (HEAD: <short-sha>)_
_Previous session checkpoint: mcp memory #NNNNN (if any)_

## Task goal

<One sentence describing what "done" looks like.>

## What's done

- <commit sha or file path> — <what it accomplished>
- <commit sha or file path> — <what it accomplished>

## In-flight (uncommitted)

- `path/to/file.py` — <what's half-done, what remains>
- `path/to/other.py` — <what's half-done, what remains>

## Next moves (in order)

1. <immediate next step> — acceptance criterion: <observable outcome>
2. <step after that>      — acceptance criterion: <observable outcome>
3. <step after that>      — acceptance criterion: <observable outcome>

## Suggested skills

- **`/keep:tdd`** — for next move #1 (implementing the cancellation policy)
- **`/keep:design-interface`** — for next move #2 (payment router shape)
- **`/keep:diagnosing-bugs`** — only if move #1 surfaces unexpected behaviour

## Open questions for the next agent

- <question 1> — context: <why this matters>
- <question 2> — context: <why this matters>

## Decisions made (don't re-litigate)

- <decision 1> — because <reason>
- <decision 2> — because <reason>

## Pointers (do not duplicate — read these)

- PRD: `docs/prd/orders-cancellation.md`
- Plan: `.sprint/<task>/PLAN.md` (task dir via `sprint-plan path`)
- Prior review: `<commit sha>` / `mcp__mind__search "orders-cancellation-review"`

## Environment notes

- <anything non-obvious about the environment the next agent needs>
```

**Rules:**

- **Point, don't duplicate.** If a PRD / plan / ADR / commit / diff already captures something, reference it by path or URL. Don't paraphrase — paraphrases drift.
- **Decisions are immutable in the handoff.** The next agent reads them as constraints, not as questions to reopen.
- **Open questions are different from decisions** — they're the things the previous agent couldn't resolve and is explicitly delegating.

### 5. Echo and close

- [ ] Echo the handoff path to the user
- [ ] Echo the top 3 next moves and suggested skills inline (one line each)
- [ ] **Close by intent** — purpose picks the mode, not who pulled the trigger:
  - **Continuity mode** (hooks fired at the context ceiling, or the user
    invoked `/keep:handoff` mid-task WITHOUT fork intent — e.g. wanting a
    quality snapshot before auto-compact): the handoff doc now doubles as the
    pre-compact snapshot. **Resume the interrupted task immediately in this
    same session.** Do NOT end the turn, do NOT direct the user to run
    `/compact` — native auto-compact fires on its own, and
    `post-compact-bridge.sh` re-points the compacted context at this doc so
    dropped details are recoverable. Zero human intervention is the contract;
    ending the turn here is the bug this mode exists to fix.
  - **Fork mode** (the invocation expresses fork intent — machine switch,
    "pass this off", hand the baton to a new session): end here. The doc is
    the baton — remind the user how the next session consumes it:

    ```
    Next session: cat $HOME/.claude/handoffs/keep-handoff-<timestamp>.md
                  mcp__mind__wakeup(project)  # reload memory state
                  /keep:<suggested skill>  # begin next move
                  rm $HOME/.claude/handoffs/keep-handoff-<timestamp>.md  # one-shot — delete after consuming
    ```

## Resource Check

| Resource | How to check | Degraded mode |
|----------|-------------|---------------|
| `mind` | `mcp__mind__search` available | Skip "Previous session checkpoint" pointer |
| `git-diff` | Repo is git | Note as "no git context — rely on file mtimes" |

## Anti-Patterns

- ❌ **Writing handoffs into the repo.** Use the pinned dir (`$HOME/.claude/handoffs`). The repo shouldn't carry disposable state.
- ❌ **Writing handoffs to `$TMPDIR`/`/tmp`.** The compact-gate hooks scan the pinned dir only; a tmp write deadlocks `/compact` on macOS (per-process `TMPDIR` drift between writer shell and hook env).
- ❌ **Leaving the handoff file in the dir after the next session consumes it.** It's one-shot — the consumer must `rm` after reading.
- ❌ **Paraphrasing existing artifacts.** If a PRD exists, cite it. Don't retell it.
- ❌ **Reopening decisions.** Hand off decisions as constraints. If you want to reopen, list under "Open questions" with reasoning.
- ❌ **Skipping sanitisation.** API keys in a handoff file in `/tmp` is still a leak.
- ❌ **Using handoff when compact would do** (user-initiated). Handoff is for forks; same-session compression is `/compact`. Hook-triggered continuity snapshots are the exception — the hooks invoke them, not preference.
- ❌ **Omitting suggested skills.** The next agent shouldn't have to re-derive which skill fits — name them.

## Composability

- **Input ← grilling**: a deep grilling session that detours into `/keep:prototype` should handoff before the detour and consume the handoff after.
- **Input ← sprint**: if sprint Phase 3 (Implement) is interrupted, handoff captures the in-flight modules.
- **Output → wakeup**: next session's `mcp__mind__wakeup(project)` reads memory state, then the operator reads the handoff file — they compose.
- **Output → route**: a handoff with named suggested skills is a route input — the next session can read those first.
- **Differs from session-checkpoint**: checkpoint is structured memory for `wakeup()`; handoff is a human-and-agent-readable document for conscious continuation. Both may exist for the same transition.
