---
name: keep:route
version: "1.0"
triggers: ["/keep:route", "/keep:ask", "/keep:which skill", "/keep:help me choose", "/keep:what should I use"]
description: >
  Router skill — index every user-invoked skill in the keep directory and tell the
  user which one fits their situation. TRIGGER when: user says "/keep:route",
  "/keep:ask", "which skill should I use", "help me choose", is unsure which workflow
  applies, or starts with a vague request that could match several skills. Presents
  a decision tree, asks at most one clarifying question, then routes. Do NOT trigger
  for: requests where the matching skill is obvious, or pure-read queries (answer
  directly).
resources: []
---

# Route

Index of every user-invoked skill in this directory. You don't need to memorise 24 skills — describe your situation and this skill points at the right one.

## The Main Flow (idea → ship)

Most engineering work walks this path. Pick the phase that matches where you are.

```
  idea
   │
   ▼
┌──────────────────┐    requirements vague?    ┌──────────────────┐
│  /keep:grilling  │ ◄──────────────────────── │   (you are here) │
│  Align before    │                           └──────────────────┘
│  coding          │
└────────┬─────────┘
         │ plan locked
         ├──────────────────────────┐
         │ single session           │ multi-session / PRD needed
         ▼                          ▼
┌──────────────────┐      ┌──────────────────┐    ┌──────────────────┐
│  /keep:sprint    │      │  /keep:to-prd    │ ─► │ /keep:to-issues  │
│  Research → Plan │      │  Synthesise the  │    │ Vertical slices  │
│  → Implement →   │      │  locked plan     │    │ ready-for-agent  │
│  Review → Ship   │      │  (no interview)  │    └────────┬─────────┘
└────────┬─────────┘      └──────────────────┘             │
         │                                                  │ per issue
         │ interface unclear?                               ▼
         ▼                                     ┌──────────────────┐
┌──────────────────┐                          │  fresh session:  │
│/keep:design-     │                          │  /keep:tdd  ←──┐ │
│  interface       │                          └────────────────┘ │
│  Design It Twice │                                              │
└────────┬─────────┘                                              │
         │ interface locked                                        │
         ▼                                                         │
┌──────────────────┐                                              │
│   /keep:tdd      │ ─────────────────────────────────────────────┘
│   Red-Green-     │
│   Refactor       │
└────────┬─────────┘
         │ code written
         ▼
┌──────────────────┐
│  /keep:review    │
│  Multi-agent     │
│  cross-check     │
└────────┬─────────┘
         │ findings addressed
         ▼
┌──────────────────┐
│   /keep:deslop   │
│   Strip AI slop  │
└────────┬─────────┘
         │ clean
         ▼
       shipped
```

**Two branches after grilling:**

- **Single session** → `/keep:sprint` does Research → Ship in one pass.
- **Multi-session / PRD needed** → `/keep:to-prd` publishes the locked plan → `/keep:to-issues` decomposes into vertical slices → each slice runs in a fresh session via `/keep:tdd`.

**Bug path** branches off at any phase — when something is broken rather than being built:

```
  bug report / regression / flaky test
   │
   ▼
┌──────────────────────┐
│/keep:diagnosing-bugs │  →  (after fix) → /keep:tdd for regression test
│ Six-phase debug loop │
└──────────────────────┘
```

**Ball-of-mud path** is a parallel health check, not part of idea→ship:

```
  codebase feeling tangled / tests getting harder
   │
   ▼
┌─────────────────────────┐
│/keep:architecture-scan  │ → ranked report → pick one →
│ Find deepening wins     │     /keep:design-interface + /keep:grilling
└─────────────────────────┘
```

**Triage path** handles external-sourced issues (not your own plan — those go through `to-prd`/`to-issues`):

```
  bug report / review finding / external request  (someone else's input)
   │
   ▼
┌────────────────────┐    category?    ┌─────────────────────────┐
│   /keep:triage     │ ──────────────► │ bug  → /keep:diagnosing │
│ State machine:     │                 │ feat → /keep:to-prd     │
│ raw → triaged →    │                 │ cln  → /keep:deslop     │
│ assigned → done    │                 │ q    → answer, close    │
└────────────────────┘                 └─────────────────────────┘
```

**Learning path** is orthogonal to idea→ship — it builds the human, not the product:

```
  user wants to learn a skill/concept across multiple sessions
   │
   ▼
┌────────────────────┐
│   /keep:teach      │ → profile in memory → curriculum →
│ Multi-session      │     per-session lessons + spaced repetition
│ teaching loop      │
└────────────────────┘
```

## On-Ramps (specialised entry points)

These don't fit the main flow — they have their own triggers.

| Situation | Use | Why |
|-----------|-----|-----|
| Large/unknown file or directory to understand | `/keep:analyze` | RLM-style chunk + parallel + merge |
| Browser automation (scrape, E2E test, replay) | `/keep:browser-use` | Headless with domain knowledge |
| Background monitoring of files / state | `/keep:ambient` | Watch without active prompting |
| Project jargon is fuzzy or inconsistent | `/keep:ubiquitous-language` | Extract and harden glossary (inline or batch) |
| Token / cost / context visibility | `/keep:statusline` | Status bar setup |
| First-run personalisation | `/keep:onboard` | Wizard — run once |
| Configuring keep itself (hooks, skills, rules) | `/keep:harness` | Self-modification |
| Reusable pattern discovered → save as skill | `/keep:skill-forge` | Auto-extract from experience |
| Unattended automation across revolutions | `/keep:loop` | Five-move loop with evaluator gate |
| Codebase feels like a ball of mud | `/keep:architecture-scan` | Ranked deepening-opportunities report |
| Design question code can answer faster than prose | `/keep:prototype` | Disposable worktree prototype, synthesize, teardown |
| Switching machines / agents / contexts mid-work | `/keep:handoff` | Cross-session handoff doc with suggested next skills |
| Backlog of unsorted external issues (bugs, review findings, requests) | `/keep:triage` | State machine: raw → triaged → assigned → done |
| Learning a skill or concept over multiple sessions | `/keep:teach` | Curriculum + spaced repetition; profile in memory |

## Routing Protocol

### 1. Classify

Read the user's request. Decide:

- **Phase match?** → main flow column above.
- **Bug language?** ("broken", "failing", "regression", "flaky") → `/keep:diagnosing-bugs`.
- **On-ramp match?** → table above.
- **Pure read query?** ("what does X do", "list Y") → answer directly, don't route.

### 2. One clarifying question (max)

If classification is ambiguous, ask **one** question with a recommendation:

> "Sounds like you want to build a new feature end-to-end. _Recommended: `/keep:sprint` — because it covers Research → Ship in one pass._ Or did you mean to pressure-test the plan first (`/keep:grilling`)?"

Not:

> "What do you want to do? Here are 24 options..."

### 3. Hand off

Once classified, **name the skill and its trigger** in one line, then stop. Do not summarise the target skill's content — that is the user's next prompt, not yours.

```
Use /keep:grilling — it'll interview you one question at a time before you touch code.
```

If two skills apply, name both and say which to run first.

```
Run /keep:grilling first to lock the plan, then /keep:sprint to ship it.
```

## When NOT to Route

- User's request is a read-only question. Answer from context.
- The matching skill is obvious from the user's phrasing (they named it).
- User is mid-skill already — let that skill finish.
- Request is trivial (1 file, <5 lines, no design). Just do it.

## Index at a Glance

| Skill | Phase | One-line job |
|-------|-------|--------------|
| `grilling` | Align | Interview until the plan is unambiguous |
| `ubiquitous-language` | Align | Build and sharpen project glossary (inline + batch) |
| `to-prd` | Plan | Synthesise locked plan into a published PRD |
| `to-issues` | Plan | Decompose PRD into agent-ready vertical slices |
| `triage` | Plan | Move external-sourced issues through a state machine |
| `prototype` | Plan | Disposable prototype in worktree — code answers design questions |
| `sprint` | Build | Research → Plan → Implement → Quality Gate → Review → Test → Ship → Reflect |
| `design-interface` | Design | Generate 3+ radical interface designs, compare |
| `tdd` | Build | Red-green-refactor, vertical tracer bullets |
| `review` | Verify | Multi-agent cross-validation (bug + security + adversarial + evaluator) |
| `deslop` | Clean | Strip AI-generated code slop from recent changes |
| `diagnosing-bugs` | Fix | Six-phase debug loop, tight red loop is the gate |
| `architecture-scan` | Audit | Ranked deepening-opportunities report for the codebase |
| `analyze` | Understand | Chunk + parallel + merge for large artifacts |
| `teach` | Learn | Multi-session teaching with spaced repetition |
| `handoff` | Tool | Cross-session handoff doc with suggested next skills |
| `browser-use` | Tool | Headless browser automation |
| `ambient` | Tool | Background context monitoring |
| `skill-forge` | Meta | Auto-extract reusable skill from experience |
| `loop` | Meta | Five-move unattended loop with evaluator gate |
| `harness` | Meta | Modify keep itself |
| `onboard` | Setup | First-run personalisation wizard |
| `statusline` | Setup | Token / cost / context status bar |
| `cross-review` | Auto | Cross-agent review after Complex task (auto-trigger) |
