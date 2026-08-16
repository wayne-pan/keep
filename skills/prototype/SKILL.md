---
name: keep:prototype
version: "1.0"
triggers: ["/keep:prototype", "/keep:spike", "/keep:throwaway", "/keep:try it out", "/keep:flesh out design"]
routes_to: ["grilling", "design-interface"]
description: >
  Build a throwaway prototype to flesh out a design — either a runnable terminal
  app (for state / business-logic questions) or several radically different UI
  variations toggleable from one route (for UX questions). TRIGGER when: user
  says "/keep:prototype", "spike this", "throwaway prototype", "try it out", or
  when a design question can't be answered by talking (code answers it faster
  than prose). Output is disposable by design — uses worktree isolation and
  explicit teardown. Do NOT trigger for: production features (use /keep:sprint),
  or questions answerable from existing code (read it first).
resources: ['subagents', 'git']
---

# Prototype

Build a throwaway prototype to answer a design question code can answer faster than prose. The prototype is **disposable** — its purpose is to surface information, not to ship. Keep it out of the main branch.

When to prototype vs not:

| Question type | Tool |
|---------------|------|
| "Will this state machine terminate / what are the edge cases?" | Prototype (terminal) |
| "Does this UI feel right with three columns vs two?" | Prototype (UI variations) |
| "What's the right data shape for this concept?" | Prototype (terminal) — code surfaces constraints prose hides |
| "How should this module be designed?" | `/keep:design-interface` — not a prototype |
| "What does the user want?" | `/keep:grilling` — not a prototype |

## Two Modes

| Mode | When | Output |
|------|------|--------|
| **terminal** | State machine, business logic, data shape, algorithmic question | A runnable Python/Node script in `bin/` or a single-file program |
| **ui-variations** | Visual / interaction design question | Multiple UI variations toggled from one route — `?variant=A`, `?variant=B`, `?variant=C` |

Default recommendation by question type. If unclear, ask the user **one** question.

## Hard Rules

1. **Worktree isolation, mandatory.** Use `EnterWorktree` before writing any prototype code. The prototype never edits the main tree.
2. **Time-boxed.** State the budget up front (default: 1 hour, 2 hours max). If the prototype isn't answering the question by then, the question is bigger than you thought — escalate to `/keep:grilling`.
3. **Disposable by intent.** The prototype's purpose is to inform the production design, not to *become* it. State this in the worktree commit message.
4. **One question per prototype.** If two design questions, two prototypes. Mixing muddies both answers.
5. **End with synthesis, not merge.** The output is a written answer to the design question, not a PR.

## Workflow

### Phase 1 — Frame

- [ ] State the design question in **one sentence** (the thing the prototype must answer)
- [ ] Pick the mode (terminal or ui-variations) with a recommendation
- [ ] State the budget (default: 60 minutes)
- [ ] State the **done-when** criterion: what observable outcome answers the question?
- [ ] `EnterWorktree` with a descriptive name (e.g. `prototype-orders-state-machine`)
- [ ] **Seed in-flight files** into the worktree — `EnterWorktree` branches from HEAD, so dirty/untracked files in the main tree do not follow. Run the marked snippet below with both env vars set.

```
Question: "Does the order-cancellation state machine have a terminating path when
          the payment refund fails after inventory has been released?"
Mode: terminal (state machine question, no UI)
Budget: 60 minutes
Done when: I can name every path through the machine and identify any non-terminating ones
```

<!-- seed-begin -->
```bash
# Seed dirty/untracked files from the main repo into a fresh worktree.
: "${SEED_SRC:?export SEED_SRC=<main-repo-dir>}" "${SEED_DST:?export SEED_DST=<worktree-dir>}"
git -C "$SEED_SRC" status --porcelain -uall | cut -c4- | grep -Ev '\.(log|tmp)$' | while IFS= read -r f; do
  mkdir -p "$SEED_DST/$(dirname "$f")"
  cp "$SEED_SRC/$f" "$SEED_DST/$f" 2>/dev/null || true
done
```
<!-- seed-end -->

**Done when:** worktree created, question/mode/budget/done-when written at the top of the prototype's README.

### Phase 2 — Build (terminal mode)

Write the smallest program that *embodies the question*:

- A state machine → encode the transitions as data, run it with a fuzz or enumeration
- A business logic question → write the core function with synthetic inputs
- A data-shape question → define the types, write 3-5 example values, see which feel wrong

**Rules:**

- No I/O polish. No error handling for failure modes the prototype can't produce. No tests. No README beyond the framing paragraph.
- No persistence. Hardcode inputs as fixtures. The goal is to *see the answer*, not ship.
- Use the simplest tool that runs. Python script, Node script, even a Jupyter notebook if the question is exploratory.

### Phase 2 — Build (ui-variations mode)

Spawn parallel sub-agents (this is where `subagents` resource pays off):

| Sub-agent | Constraint |
|-----------|-----------|
| Agent A | Build variation A with constraint X (e.g. "three columns, density-first") |
| Agent B | Build variation B with constraint Y (e.g. "two columns, focus-first") |
| Agent C | Build variation C with constraint Z (e.g. "single column, mobile-first") |

Wire all variations behind one route:

```
GET /prototype?variant=A  → variation A
GET /prototype?variant=B  → variation B
GET /prototype?variant=C  → variation C
```

Each variation should be **radically different**, not a styling tweak. If they look similar, the agents converged — redo with stronger constraints.

### Phase 3 — Run and observe

- [ ] Run the prototype
- [ ] Capture the observable output (terminal trace, screenshot, screen recording)
- [ ] Note where the answer surprised you vs confirmed the hypothesis
- [ ] Note any **new questions** the prototype surfaced (these are gold — they become grilling or design-interface inputs)

**Done when:** the design question from Phase 1 has a written answer backed by the prototype's behaviour.

### Phase 4 — Synthesise

Write the answer to the design question. **This is the prototype's real output — not the code.**

```md
# Prototype answer: <the design question>

## Answer

<One paragraph. The prototype showed X, which means Y for the production design.>

## Evidence

- Prototype trace: <paste 5-10 lines that show the answer>
- Surprising finding: <what you didn't expect>
- New questions surfaced: <list — these feed /keep:grilling or /keep:design-interface>

## Recommendation for production

<One paragraph. What the production code should do, informed by this prototype.>

## Disposition

The prototype lives in worktree `<name>` and is **not** merged. Its findings are
captured here. The worktree may be deleted after the production design lands.
```

### Phase 5 — Teardown decision

The user chooses:

| Option | When | Action |
|--------|------|--------|
| **Remove now** (default) | Findings captured, production design is clear | `ExitWorktree action="remove"` |
| **Keep for reference** | Production design will reference the prototype's specifics | `ExitWorktree action="keep"` — note the worktree path in the synthesis |
| **Detour through handoff** | Production design is a separate session's job | `/keep:handoff` first, then remove |

**Never merge the prototype into main.** If you find yourself wanting to, the prototype became production — that means the framing was wrong (Phase 1 didn't bound the scope). Roll back, re-frame, try again.

## Anti-Patterns

- ❌ **Prototyping in the main tree.** Always worktree. Always.
- ❌ **Polishing the prototype.** Error handling, tests, README — all waste. The prototype is disposable.
- ❌ **Mixing questions.** "Let's also see if the UI works while we're testing the state machine" — no. Two questions, two prototypes.
- ❌ **Skipping the synthesis.** The code is not the output. The written answer is. A prototype without synthesis is a science experiment with no lab report.
- ❌ **Merging the prototype.** If it became production, you misframed it.
- ❌ **Prototyping what you could read.** Read the existing code first. Only prototype what doesn't exist yet.

## Resource Check

| Resource | How to check | Degraded mode |
|----------|-------------|---------------|
| `subagents` | Agent tool available | For ui-variations: build variations sequentially (slower). For terminal: no impact. |
| `git` (worktrees) | `EnterWorktree` available | Fall back to a feature branch with explicit teardown (see note below). Riskier than worktree; only use if `EnterWorktree` is genuinely unavailable. |

**Feature-branch fallback teardown** (when worktrees unavailable):

```bash
git checkout main && git branch -D prototype-<name>
```

Without worktree isolation the prototype shares index/HEAD with main — every uncommitted change leaks. Commit-or-discard all changes before switching branches. Run the teardown only after Phase 4 synthesis is captured (in repo or handoff).

## Composability

- **Input ← grilling**: when grilling surfaces a "we can't answer this by talking" question, hand off here.
- **Input ← design-interface**: when comparing 3 designs isn't enough — actually build them.
- **Output → grilling**: new questions surfaced → next grilling session.
- **Output → design-interface**: prototype findings inform which interface design is strongest.
- **Output → handoff**: if production design is a separate session, handoff before teardown.
- **Output → to-prd**: prototype findings may rewrite the PRD — synthesise first, then update.
