---
name: keep:to-issues
version: "1.0"
triggers: ["/keep:to-issues", "/keep:break into issues", "/keep:decompose prd", "/keep:split into tasks", "/keep:vertical slices"]
routes_to: ["grilling", "tdd"]
description: >
  Break a PRD, plan, or spec into independently-grabbable issues using vertical
  slices. TRIGGER when: user says "/keep:to-issues", "break this into issues",
  "split this PRD", or after /keep:to-prd when the next step is decomposition.
  Each slice must be end-to-end (tracer bullet through all layers), independently
  demoable, and agent-ready. Includes optional prefactor detection — find changes
  that make the main work easier, do those first. Do NOT trigger for: trivial
  single-change PRDs (one issue is fine, just write it), or implementation work.
resources: ['git', 'mind']
---

# To Issues

Decompose a PRD into **vertical slices** — each slice is a tracer bullet that pierces all layers (UI → logic → data), can be demoed on its own, and can be picked up by an agent without context from the other slices.

Horizontal slicing (UI layer first, then logic layer, then data layer) is the anti-pattern. It produces unshippable intermediate states.

```
WRONG (horizontal):
  Issue 1: schema + migrations
  Issue 2: business logic
  Issue 3: HTTP endpoints
  Issue 4: UI

RIGHT (vertical):
  Issue 1: Happy path — create order → charge card → confirmation email
  Issue 2: Edge case — declined card with retry
  Issue 3: Edge case — refund flow
```

## Five Phases

### Phase 1 — Gather context

- [ ] Read the PRD (or plan / spec) the user points at
- [ ] `Glob` the relevant module paths to confirm they exist
- [ ] `mcp__mind__search "<prd topic>"` — prior decisions to respect
- [ ] Read `UBIQUITOUS_LANGUAGE.md` if it exists

**Done when:** you can name every module the PRD touches.

### Phase 2 — Explore for prefactor opportunities (optional but recommended)

Before drafting slices, look for changes that would make the main work easier. Quote: _"Make the change easy, then make the easy change."_ — Kent Beck.

Prefactor candidates:

- A missing test seam (no place to write the first test)
- A shallow module that will be touched N times — deepen it first
- A duplicated pattern that will be touched N times — extract it first
- A type hole that will cause N bugs — close it first
- A missing adapter that will require N mock setups — add it first

If you find one, it becomes **Issue #1**. The main slices come after.

**Done when:** either no prefactor is needed, or one prefactor issue is identified (more than one suggests the prefactor itself needs a `/keep:architecture-scan`).

### Phase 3 — Draft vertical slices

Each slice must satisfy all of:

- [ ] **End-to-end**: pierces every layer the PRD touches
- [ ] **Demoable**: produces an observable outcome a user could see
- [ ] **Agent-ready**: a fresh agent (post-`/keep:handoff`) can pick it up without reading the other slices
- [ ] **Testable at a single seam**: one test surface per slice
- [ ] **Ordered**: each slice either builds on the previous or stands alone

**Slice template:**

```md
## Slice N: <one-line outcome>

**PRD ref:** <which user stories this satisfies>
**Seam:** <module name>
**Prefactor?** No / Yes — <what>

### What changes

<2-3 sentences at the module level. No file paths.>

### Acceptance criteria

- [ ] <observable behaviour 1>
- [ ] <observable behaviour 2>
- [ ] <test asserts these at the seam>

### Out of scope for this slice

- <explicitly excluded — belongs in another slice>

### Depends on

- Slice N-1 (or: none)

### Suggested skill

`/keep:tdd` — vertical red-green-refactor at the named seam
```

**Rules:**

- **No file paths.** Module names only — paths rot between issue creation and pickup.
- **One seam per slice.** If a slice touches two seams, it's two slices.
- **Acceptance criteria are observable.** "Code is cleaner" is not. "POST /orders returns 201 with the created order ID" is.
- **Dependencies are explicit.** A slice that depends on Slice N-1 must say so.

### Phase 4 — Quiz the user

Show the slices. Ask **at most three** questions, each with a recommendation:

1. **Granularity** — too coarse, too fine, or right? _Recommended: <your call — based on PRD size>_
2. **Dependencies** — are any slices actually independent that you've chained? _Recommended: <your call>_
3. **Missing slices** — anything you'd add or merge? _Recommended: <your call>_

Iterate until the user approves. **Never** publish unapproved — Phase 4 approval is the single gate; Phase 5 does not re-confirm.

**Approval scales with tracker blast radius** (mirrors `/keep:to-prd` Phase 4):

| Tracker | Reversibility | What "approval" means |
|---------|---------------|------------------------|
| **GitHub / Linear** | Irreversible public action (each slice gets `ready-for-agent`, signals agents may auto-pick) | User approved the full slice set in Phase 4 — that approval covers publishing all slices |
| **local** (`.issues/<slug>-slice-N.md`) | Fully reversible — edit or delete the files | Lightweight: user saw the slice list in Phase 4; writing to disk needs no extra gate |

**Done when:** user approves the slice set and ordering.

### Phase 5 — Publish

Order matters — publish in dependency order. Agents pick up the first un-started slice.

| Tracker | Action per slice |
|---------|------------------|
| GitHub | `gh issue create --title "Slice N: <outcome>" --body "$(cat slice-N.md)" --label "ready-for-agent"` |
| Linear | Linear CLI create |
| local | Write each to `.issues/<slug>-slice-N.md` |

Then:

- [ ] Echo the issue URLs/paths
- [ ] Note the recommended pickup order
- [ ] Suggest: for the first slice, start with `/keep:tdd` in a fresh session

## Anti-Patterns

- ❌ **Horizontal slicing.** "First all the schemas, then all the logic" produces unshippable PRs.
- ❌ **Mega-slices.** If a slice takes more than a session, it's two slices.
- ❌ **File paths in the body.** Paths rot. Use module names.
- ❌ **Implicit dependencies.** If Slice 2 needs Slice 1, say so. Surprise dependencies break agent pickup.
- ❌ **Publishing without user approval.** The user has context you don't — let them reorder.
- ❌ **Skipping the prefactor.** "Make the change easy, then make the easy change." A 30-minute prefactor can save three slices of pain.
- ❌ **Specifying implementation.** The issue says *what* and *acceptance*, not *how*. *How* is the agent's job in the slice.

## Resource Check

| Resource | How to check | Degraded mode |
|----------|-------------|---------------|
| `git` | `git rev-parse --is-inside-work-tree` | Skip module-shape verification; warn user |
| `mind` | `mcp__mind__search` available | Skip prior-decisions check |
| `gh` | `command -v gh && gh auth status` | Fall back to local `.issues/` |

## Composability

- **Input ← to-prd**: PRD is the canonical input. Read it directly.
- **Output → tdd**: each slice is a `/keep:tdd` engagement waiting to happen.
- **Output → handoff**: when a slice is finished mid-session, handoff to a fresh session for the next slice.
- **Output → loop**: slices published with `ready-for-agent` labels are loop discovery fuel.
- **Output → sprint**: a single slice is a sprint input.
- **Input ← architecture-scan**: if a scan surfaces shallow modules in the PRD's path, run prefactor slices first.
