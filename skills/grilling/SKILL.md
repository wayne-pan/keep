---
name: keep:grilling
version: "1.0"
triggers: ["/keep:grilling", "/keep:grill me", "/keep:interview me", "/keep:pressure test", "/keep:interrogate plan", "/keep:challenge assumptions", "/keep:align before coding"]
routes_to: ["ubiquitous-language", "design-interface"]
description: >
  Relentless pre-coding alignment interview. TRIGGER when: user is about to build a
  feature or make a non-trivial change but the plan is still fuzzy, user says
  "/keep:grill me", "/keep:align before coding", "interview me about", "pressure test
  this plan", or before sprint Phase 2 (Plan) when requirements are vague. Walks the
  decision tree one question at a time, each with a recommended answer. Three modes:
  light (no codebase), standard (read codebase first), deep (also hardens
  UBIQUITOUS_LANGUAGE.md and proposes ADRs). Do NOT trigger for: trivial edits,
  post-hoc review, or when the user explicitly says they want to skip alignment.
resources: ['mind']
---

# Grilling

Interview the user relentlessly about a plan or design until every branch of the decision tree is resolved. **One question at a time. Each question comes with a recommended answer. Stop when the user can no longer surprise you.**

The discipline that fixes the #1 failure mode in AI-assisted dev: **misalignment**. You think the agent knows what you want; the agent builds something else. Grilling closes that gap before a line of code is written.

Uses vocabulary from `rules/architecture-language.md`: module, interface, seam, adapter, depth, leverage, locality.

## Three Modes

Pick the mode by asking the user **once**, at the start:

| Mode | When | What it adds |
|------|------|--------------|
| **light** | No codebase, or pure design discussion | Just the interview |
| **standard** | Codebase exists | Read the code first; cite `file:line` instead of asking what the user already knows |
| **deep** | Long-running project, decisions worth preserving | `standard` + inline updates to `UBIQUITOUS_LANGUAGE.md` + proposes ADRs (gated by the ADR criteria below) |

Default recommendation: **standard** if a repo is present, else **light**. Use **deep** only when the user signals this is a load-bearing decision (long-lived module, cross-cutting change, hard to reverse).

## Hard Rules

1. **One question at a time.** Wait for the answer before asking the next. No question dumps.
2. **Every question ships with a recommendation.** Format: `_Recommended: X — because [one-line reason]._` The user can accept, reject, or defer. Never ask open-ended without a stake in the ground.
3. **Code over questions.** If the codebase, memory, or `UBIQUITOUS_LANGUAGE.md` can answer the question, **read it — don't ask**. Asking what you can read wastes the user's time and signals you haven't done your homework.
4. **Cite or ask, never guess.** When you read the answer, cite `file:line`. When you can't, ask. Never synthesize a plausible-sounding answer and proceed.
5. **Stop when branches are closed.** Done when the user cannot produce a follow-up question you haven't already resolved. Not when you run out of your prepared list.

## Workflow

### 1. Frame (one exchange)

Ask the user **one** question: what are we pressure-testing, and which mode?

Then state in 2-3 lines what you believe the decision tree looks like at a high level — the load-bearing branches. The user corrects the shape before you descend.

**Done when**: user confirms the tree shape and mode.

### 2. Recon (standard / deep only)

Before the first substantive question:

- [ ] `Glob` the relevant module paths
- [ ] `Grep` for the terms the user used — check `UBIQUITOUS_LANGUAGE.md` for canonical names
- [ ] `mcp__mind__search` for past decisions on this area (`project=<basename>`)
- [ ] Read the 2-3 files most likely to constrain the answer

Output a one-paragraph summary: "Here's what I already know from the code and memory: ...". Then begin.

**Done when**: you can name the modules, seams, and adapters that will be touched, citing `file:line`.

### 3. Descend the tree

Repeat until branches are closed:

1. Pick the next unresolved branch (deepest load-bearing one first).
2. If answer is in code or memory: state it with citation, mark branch resolved, continue.
3. If not: ask **one** question with a recommendation. Wait. Resolve. Continue.

After every 3-4 resolutions, restate the tree shape with closed branches marked, so the user can see convergence.

### 4. Synthesize (deep mode adds inline artifacts)

While descending, in **deep** mode:

- **Terminology**: when a term gets sharpened or canonicalized mid-interview, update `UBIQUITOUS_LANGUAGE.md` inline (do not batch). Use `/keep:ubiquitous-language` rules: opinionated, flag ambiguities.
- **ADR**: propose an ADR **only** when all three are true:
  1. The decision is **hard to reverse** (touches public interface, schema, or cross-cutting convention).
  2. Someone returning to this code without context would be **confused without background**.
  3. There is a **real trade-off** (not just "we picked the obvious one").

  When all three hold, write `docs/adr/NNNN-<slug>.md` using the project's ADR format if one exists; otherwise ask. Do not batch — write as the decision lands.

**Done when**: every branch is resolved, artifacts (if deep) are written, and the user cannot surprise you with a new question.

## What Good Looks Like

```
You: We're pressure-testing the order-cancellation flow. I'll use standard mode.
     The load-bearing branches I see:
       (a) who can cancel (customer / admin / system)
       (b) cancellation window (time-bound / state-bound / none)
       (c) side effects (payment refund, inventory release, notification)
     Correct the shape before I descend.

User: Shape's right. Start with (b).

You: Code already answers part of this — `orders/cancel.py:42` enforces a 24h window
     from `created_at`. So (b) is state-bound *via* a time invariant, not pure state.
     _Recommended: keep as-is — adding pure-state cancellation would split the rule
     across two code paths._
     Accept?

User: Accept. Move to (a).

You: (a) — who can cancel. `policy.py:18` lists `customer` and `admin`. No `system`
     path. But you mentioned auto-cancellation in your framing.
     _Recommended: add `system` as a third actor, gated by inventory-breach events —
     because the existing two-actor model has no hook for upstream cascades._
     Accept / reject / defer?
```

## What Bad Looks Like

- ❌ "Tell me about your requirements." (no recommendation, no shape, no recon)
- ❌ Asking 5 questions in one turn (violates rule 1)
- ❌ Asking what `policy.py` already says (violates rule 3)
- ❌ Stopping at your prepared list without checking the user has no more branches (violates rule 5)
- ❌ In **deep** mode, batching all terminology updates to the end (loses the inline discipline)

## Exit Criteria

- [ ] Every load-bearing branch has a recorded resolution
- [ ] Every resolution traces to either a `file:line` citation, a memory hit, or a user answer
- [ ] In **deep** mode: `UBIQUITOUS_LANGUAGE.md` updated inline; ADRs written only where all three criteria hold
- [ ] User cannot produce a follow-up question you haven't already resolved
- [ ] Hand-off ready: the next agent (sprint / tdd / design-interface) can start without re-aligning

## Composability

- **sprint** should call `grilling` (standard mode) between Phase 1 (Research) and Phase 2 (Plan) when requirements are vague.
- **design-interface** benefits from a grilling pre-pass — sharpen the problem statement before spawning parallel design sub-agents.
- **tdd** Phase 1 (Planning) is a thin grilling pass scoped to "what behaviors to test".
- **loop** generators may run grilling on the user's behalf for Move 1 (Discovery) when the spec is ambiguous.
