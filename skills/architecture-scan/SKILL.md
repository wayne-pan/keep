---
name: keep:architecture-scan
version: "1.0"
triggers: ["/keep:architecture scan", "/keep:scan architecture", "/keep:find shallow modules", "/keep:deepening opportunities", "/keep:ball of mud", "/keep:architectural debt"]
routes_to: ["design-interface", "grilling", "ubiquitous-language"]
description: >
  Scan the codebase for architectural deepening opportunities — shallow modules,
  pass-throughs, leaked coupling, hard-to-test interfaces. TRIGGER when: user says
  "/keep:architecture scan", "find shallow modules", "rescue ball of mud",
  "architectural debt", "where should we deepen", or runs it as a periodic health
  check (recommended every few days on active codebases). Three phases: Explore
  (sub-agent walkthrough) → Report (ranked candidates with deletion-test verdicts)
  → Deepen (hand off to /keep:design-interface + /keep:grilling on the chosen one).
  Do NOT trigger for: single-file review (use /keep:review), greenfield code with
  no history, or trivial codebases (<5 modules).
resources: ['subagents', 'mind', 'git-diff']
---

# Architecture Scan

Find where the codebase is shallower than it should be, and rank those places by deepening leverage. This is the skill that combats the **ball of mud** failure mode — the asymptotic complexity growth that AI-accelerated code produces faster than human-written code.

Pairs with `/keep:design-interface` (deepens one chosen module) and `/keep:deslop` (cleans surface slop without restructuring).

Uses vocabulary from `rules/architecture-language.md`: **module**, **interface**, **implementation**, **depth**, **seam**, **adapter**, **leverage**, **locality**, **deletion test**.

## Three Phases

### Phase 1 — Explore (sub-agent walkthrough)

Spawn one or more `Explore` sub-agents to walk the codebase organically — not by directory listing, but by following call chains and data flow.

**Sub-agent prompt template:**

```
Walk the codebase at <path> looking for architectural debt. For each finding,
report:
  - Module path (file:line of the interface)
  - Symptom (what's shallow / leaky / hard to test)
  - Evidence (concrete call sites, duplication count, test pain)
  - Deletion-test verdict (see below)
  - Estimated deepening leverage (Low / Medium / High)

Look specifically for:
  1. Shallow modules — large interface, thin implementation, pass-through behaviour
  2. Leaked coupling — caller reaches past an interface into another module's internals
  3. Test pain — tests require excessive setup, mock heavy, or can't be written at the interface
  4. Duplication — same logic in N places because no module earned it
  5. Shotgun surgery — one conceptual change touches many files
  6. Sediment — dead branches, retired abstractions, defensive checks for failure modes that can't occur

Apply the deletion test to each candidate:
  - Delete the module in your head. Does complexity vanish (pass-through, delete it)?
  - Or does complexity reappear across N callers (earned its keep, deepen instead)?

Do not propose fixes. Only diagnose.
```

**Multi-sub-agent strategy** for larger codebases:

| Sub-agent | Scope |
|-----------|-------|
| Agent A | Core domain modules |
| Agent B | Adapters / external integrations |
| Agent C | Test files (look for test pain symptoms) |
| Agent D | Cross-cutting concerns (auth, logging, error handling) |

Run in parallel. Collect their reports.

**Done when:**

- [ ] Every directory with non-trivial code has been walked
- [ ] Each candidate has a deletion-test verdict (pass-through vs earned)
- [ ] Each candidate has at least one concrete code citation (`file:line`)
- [ ] `mcp__mind__search` checked for prior architectural decisions on the same modules (avoid re-proposing settled questions)

### Phase 2 — Report (ranked candidates)

Write a markdown report to `.architecture-scan/REPORT.md` (in the working dir, git-ignored if appropriate — ask user). Markdown, not HTML — keep is offline-friendly and HTML+CDN reports don't fit.

**Report structure:**

```md
# Architecture Scan Report

_Generated: YYYY-MM-DD_
_Scope: <path>_
_Sub-agents: N_

## Summary

- N modules scanned
- M deepening candidates identified
- Top leverage area: <one-line>

## Candidates (ranked by leverage)

### 1. <Module name> — Strong recommendation

- **Path:** `src/orders/cancellation.py:42`
- **Symptom:** Pass-through — every call delegates to `policy.check()` with no added logic
- **Evidence:** 7 callers, all identical delegation pattern. Deletion test: complexity vanishes.
- **Deletion-test verdict:** pass-through (delete)
- **Leverage:** High — removing it removes 7 call-site references and a layer of indirection
- **Before:**
  ```
  caller → CancellationService → policy.check()
  ```
- **After (proposed direction):**
  ```
  caller → policy.check()
  ```
- **Risks:** None identified — purely a deletion

### 2. <Module name> — Worth exploring

- **Path:** `src/payments/router.py:18`
- **Symptom:** Shallow module — 12-method interface hiding ~30 lines of implementation
- **Evidence:** Tests at this interface require 200 lines of setup. Two methods are never called in production code.
- **Deletion-test verdict:** earned its keep, but shape is wrong
- **Leverage:** Medium — deepening (12 methods → 3) would halve test setup
- **Before / After:** ...
- **Risks:** Public interface — touching it requires migration

### 3. ...

## Not scanned

- `<path>` — excluded because <reason>

## Settlements (do not re-propose)

- `<module>` — prior decision (memory hit #NNNNN) chose current shape because <reason>
```

**Ranking criteria:**

| Tier | When |
|------|------|
| **Strong recommendation** | High leverage, low risk, deletion-test passes (pass-through) or obvious reshape |
| **Worth exploring** | Medium leverage, real but recoverable risk, requires design work |
| **Speculative** | High leverage but high risk; or insufficient evidence; or contested prior decisions |

**Done when:**

- [ ] Report written to `.architecture-scan/REPORT.md`
- [ ] Every candidate has path / symptom / evidence / verdict / leverage / risks / before-after
- [ ] Settlements section lists prior decisions that should not be re-litigated
- [ ] User has been shown the top 3 candidates as a summary inline

### Phase 3 — Deepen (hand off)

User picks one candidate. Hand off:

- **To `/keep:design-interface`** — generate 3+ radical interface designs for the chosen module
- **Then to `/keep:grilling` (standard or deep mode)** — pressure-test the chosen design
- **Inline `/keep:ubiquitous-language`** — if the module rename surfaces a terminology sharpening
- **After implementation, to `/keep:review`** — verify the deepening didn't break callers

**Done when:**

- [ ] One candidate chosen (or user defers all)
- [ ] Hand-off skill invoked with full context (cite the report section)
- [ ] If all candidates deferred: write a one-line note to `mcp__mind__remember` so the next scan doesn't re-raise them as Strong

## Anti-Patterns

- ❌ **Proposing fixes during Explore.** Diagnosis first; design happens after the user picks.
- ❌ **Re-proposing settled decisions.** Always `mcp__mind__search` for prior context.
- ❌ **Skipping the deletion test.** A module that fails the deletion test should be deleted, not deepened — deepening a pass-through makes it worse.
- ❌ **HTML/CDN reports.** keep is offline-friendly — markdown only.
- ❌ **Scanning greenfield code.** No history means no debt to find. Wait until the code has been used.

## Resource Check

| Resource | How to check | Degraded mode |
|----------|-------------|---------------|
| `subagents` | Agent tool available | Fall back to manual Grep+Read walkthrough (slower, less thorough) |
| `mind` | `mcp__mind__search` available | Skip "Settlements" section — risk re-raising prior decisions |
| `git-diff` | `git log --oneline -20` returns data | Skip sediment detection (can't tell dead branches from live ones) |

## When to Run

- Before a major refactor
- After a sprint that touched many files (`/keep:sprint` Phase 8 Reflect can trigger this)
- Periodically on active codebases (every few days of heavy AI-assisted work)
- When onboarding to an unfamiliar codebase (replaces ad-hoc "let me look around")
- When tests are getting harder to write (test pain is a leading indicator)

## Composability

- **Input ← sprint Phase 8 (Reflect)**: if FINDINGS.md mentions architectural pain, hand off here.
- **Input ← review**: if `/keep:review` flags systemic issues, run this scan to map the full surface.
- **Output → design-interface**: every Strong / Worth-exploring candidate becomes a design-interface target.
- **Output → ubiquitous-language**: module renames almost always sharpen domain terms.
- **Output → loop**: a Move 1 (Discovery) generator can run this scan to find architectural work for the loop.
