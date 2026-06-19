---
name: keep:diagnosing-bugs
version: "1.0"
triggers: ["/keep:diagnose", "/keep:debug", "/keep:diagnosing bugs", "/keep:bug hunt", "/keep:reproduce bug", "/keep:regression hunt", "/keep:why is this broken"]
routes_to: ["tdd", "design-interface"]
description: >
  Disciplined six-phase bug diagnosis loop. TRIGGER when: user reports a bug, a test
  fails unexpectedly, a regression appears, performance degrades, or user says
  "/keep:debug", "/keep:diagnose", "why is this broken", "hunt this regression", or
  describes flaky/unexpected behavior. Phase 1 (build a tight red-green loop) is a
  hard gate — no hypothesising allowed until you can reproduce deterministically.
  Do NOT trigger for: trivial typos, compile errors with obvious fixes, or fresh
  feature work (use /keep:tdd instead).
resources: ['mind', 'git-diff']
---

# Diagnosing Bugs

A disciplined loop for hard bugs, regressions, and performance issues. **Phase 1 is everything**: until you can reproduce the bug deterministically in a tight loop, you are not debugging — you are story-telling.

Pairs with `/keep:tdd`: tdd **prevents** new bugs (red-green-refactor on new code); this skill **hunts** existing bugs.

## The Six Phases

### Phase 1 — Build the Loop (HARD GATE)

The bug must be reproducible on demand, fast, and deterministic. Without this, every later phase is guesswork.

**Done when ALL of:**
- [ ] **Red-capable** — there is a concrete command (test, curl, CLI invocation, replay) that fails when the bug is present
- [ ] **Deterministic** — running it 5x produces 5 failures, not 3-of-5
- [ ] **Fast** — under 30 seconds end-to-end (a 5-minute loop is not a loop)
- [ ] **Agent-runnable** — you (the agent) can execute it without the user babysitting

**Six clusters of loop-building techniques** (pick the cheapest cluster that gets you red-capable; rows within a cluster ordered by cost):

| Cluster | Techniques | When to reach for it |
|---------|-----------|----------------------|
| **A. Invoke code with a fixture** | (1) failing unit/integration test, (2) `curl`/HTTP replay, (3) CLI invocation | The bug is reachable through a single call site (pure logic, HTTP endpoint, or CLI). Cheapest — start here. |
| **B. Drive a real client** | (4) headless browser script (`/keep:browser-use`), (5) replay trace (recorded req/resp) | The bug lives in rendered UI, client-side state, or distributed/async flows needing real I/O. |
| **C. Glue it yourself** | (6) throwaway harness, (7) fuzz / property-based input | The bug needs custom code to surface, or only triggers on edge inputs the fixture won't reach. |
| **D. Search the history** | (8) `git bisect`, (9) differential test (old vs new build) | The bug is a regression — binary-search commits or compare builds to localise the cause. |
| **E. Escalate to the human** | (10) human-in-the-loop bash session | The bug requires runtime inspection only a human can drive (rare — escalate rather than guess). |

**Tightening**: once you have a loop, sharpen it. Faster. More deterministic. Smaller surface. A 30-second flaky loop ≈ no loop. A 2-second deterministic loop is a superpower.

**Do not proceed to Phase 2 with a flaky or absent loop.** Jumping to hypotheses is the failure mode this skill exists to prevent.

### Phase 2 — Reproduce and Minimise

- [ ] Using the loop from Phase 1, capture the **exact** failing state (stack trace, assertion message, diff, log line — verbatim, not paraphrased)
- [ ] Strip inputs to the **minimum** that still triggers the bug (minimisation makes the cause obvious; bloat hides it)
- [ ] Confirm the minimised case still fails the loop

**Done when**: the failing case is the smallest possible input/state that reproduces.

### Phase 3 — Hypothesise

Generate **3-5** candidate hypotheses. Each must be:

- **Falsifiable** — there is an observation that would disprove it
- **Specific** — names a module, a code path, a state transition
- **Ranked** — ordered by prior probability (cite `file:line` evidence, memory hits, or `git log`)

Present hypotheses to the user with the ranking and the disconfirming observation for each. Do not pick one silently — the user may have context that re-ranks them.

```
H1 (0.45): Off-by-one in window calculation — `orders/cancel.py:42` uses `<` where
          `<=` is needed. Disconfirm: assert that orders cancelled at exactly 24h
          succeed; if they still fail, H1 is wrong.
H2 (0.30): Timezone mismatch between `created_at` (UTC) and `now()` (local).
          Disconfirm: log both timestamps in ISO format with offset.
H3 (0.15): Race condition — two cancellation requests within the same second.
          Disconfirm: serialize cancellation per-order and re-run.
```

**Done when**: hypotheses are presented, user has weighed in or you have a clear winner.

### Phase 4 — Instrument (one variable at a time)

Pick the top-ranked surviving hypothesis. Add **one** instrumented observation:

- Debug log with a **unique tag** (so you can grep this run's output from later runs)
- Assertion that would fail if the hypothesis is right
- Single-variable change — do not bundle two fixes

Run the loop. Read the output verbatim.

- If hypothesis confirmed → Phase 5.
- If disconfirmed → demote it, promote the next, repeat Phase 4.
- If you burn through all hypotheses → regenerate, this time weirder (the bug is outside your current model).

**Never edit the implementation in Phase 4.** Instrumentation only. Editing while investigating muddies cause and effect.

### Phase 5 — Fix and Regression-Test

- [ ] Make the **smallest** change that flips the loop to green
- [ ] Add a regression test that **would have caught this bug** — committed with the fix
- [ ] Run the loop 5x to confirm determinism
- [ ] Run the wider suite to check you have not introduced a new bug

The regression test is the durable artifact. The fix is disposable; the test prevents recurrence.

**Done when**: loop is green, regression test committed, wider suite passes.

### Phase 6 — Cleanup and Post-Mortem

- [ ] Remove instrumentation and debug logs (use `/keep:deslop` if available)
- [ ] Ask: **"What would have prevented this bug?"**
  - Missing test seam? → consider `/keep:design-interface` to deepen the module
  - Type hole? → tighten types or add a schema
  - Concurrency footgun? → add a lint rule or invariant
  - Recurring class? → `mcp__mind__search` for similar past bugs; if found, this is a pattern — propose a deeper fix
- [ ] `mcp__mind__remember` the bug class (type=`discovery`, facts=[trigger, root cause, fix, prevention]) so the next hunt finds it
- [ ] If no good test seam exists to prevent recurrence, hand off to architecture review (`/keep:review` with security/architecture focus, or run `/keep:architecture-scan` to find deepening opportunities)

## Anti-Patterns

- ❌ **"I think the bug is..."** before Phase 1 is closed. No hypotheses without a red loop.
- ❌ **Bulk instrumentation.** One debug log, one run, one read. Then the next.
- ❌ **Fixing while investigating.** Edits during Phase 4 invalidate the loop.
- ❌ **"Works on my machine."** If you cannot reproduce it, you have not fixed it — you have hidden it.
- ❌ **Skipping the regression test.** A fix without a regression test is a future bug.
- ❌ **Skipping the post-mortem.** Phase 6 is where the skill pays forward.

## Resource Check (Phase 1 start)

| Resource | How to check | Degraded mode |
|----------|-------------|---------------|
| `mind` | `mcp__mind__search` available | Skip memory lookups; widen hypotheses |
| `git-diff` | `git diff --name-only HEAD~1` returns data | Skip `git bisect`; rely on other techniques |
| `git-bisect` | Repo has 10+ commits of history | Skip if shallow history |

## Composability

- **Output → tdd**: the regression test from Phase 5 is a tdd artifact; if the fix unlocks more behaviors, continue with `/keep:tdd`.
- **Output → design-interface**: if Phase 6 surfaces a missing test seam or shallow module, run `/keep:design-interface` on it.
- **Output → review**: if the bug class suggests a systemic gap, feed into `/keep:review` with architecture focus.
- **Input ← sprint**: sprint Phase 5 (Review) may surface bugs; route hard ones here rather than ad-hoc debugging.
