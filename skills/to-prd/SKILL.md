---
name: keep:to-prd
version: "1.0"
triggers: ["/keep:to-prd", "/keep:write prd", "/keep:synthesize prd", "/keep:publish prd", "/keep:product requirements"]
routes_to: ["to-issues", "ubiquitous-language"]
description: >
  Synthesize the current conversation into a Product Requirements Document and
  publish it to the project's issue tracker. TRIGGER when: user says "/keep:to-prd",
  "write a PRD", "turn this into a PRD", or after a deep /keep:grilling session when
  the plan is locked. Does NOT interview the user — only synthesizes what's already
  been discussed. Detects issue tracker (gh CLI for GitHub, .issues/ for local,
  Linear CLI if configured) and adapts. Do NOT trigger for: fresh conversations
  with no plan discussed (use /keep:grilling first), or implementation work.
resources: ['git', 'mind']
---

# To PRD

Synthesize the current conversation into a PRD. **No interview.** The whole point is to capture what was already discussed — if the plan isn't locked yet, route to `/keep:grilling` first.

## Four Phases

### Phase 1 — Explore

- [ ] `git log --oneline -10` — recent direction
- [ ] `mcp__mind__search "<task topic>"` — prior decisions
- [ ] `Glob` likely-touched modules (read top-level only, for module names)
- [ ] Read `UBIQUITOUS_LANGUAGE.md` if it exists — use canonical terms in the PRD
- [ ] Identify test seams — existing interfaces that already cover behaviour. Ideal count: 1. Maximum acceptable: 2. **3+ signals prefactor work is needed first** (see Anti-Patterns).

**Done when:** you can name the modules, seams, and adapters that will be touched, citing `file:line`.

### Phase 2 — Detect issue tracker

```bash
# GitHub
gh repo view --json nameWithOwner 2>/dev/null

# Linear (if configured) — binary may be `linear` or `linear-cli` depending on version
command -v linear || command -v linear-cli

# Local
[ -d ".issues" ] && echo "local"
```

| Tracker | Detection | Storage |
|---------|-----------|---------|
| **GitHub** | `gh` available + repo remote | Issue via `gh issue create` |
| **Linear** | `linear` or `linear-cli` configured | Issue via Linear API |
| **local** | `.issues/` directory exists or no tracker detected | `.issues/<slug>.md` |

If no tracker detected, default to **local** with `.issues/`. Note this to the user — they can configure `gh` later.

### Phase 3 — Write the PRD

Use this template. **Do not deviate from the structure.**

```md
# <PRD title>

_Status: ready-for-agent_
_Created: YYYY-MM-DD_
_Tracker: <github|linear|local>_

## Problem

<One paragraph. The user-facing pain. No solutions here.>

## Solution

<One paragraph. The shape of the fix at a high level. Name the modules and seams
that will change — but DO NOT specify file paths. File paths rot. Module and
seam names don't.>

## User stories

1. As a <actor>, I want <capability>, so that <benefit>.
2. As a <actor>, I want <capability>, so that <benefit>.
...
N. As a <actor>, I want <capability>, so that <benefit>.

## Implementation decisions

- <Decision 1> — because <reason>
- <Decision 2> — because <reason>

**DO NOT specify file paths here.** Reference modules and seams by their canonical names (from `UBIQUITOUS_LANGUAGE.md` if available).

**Exception:** a snippet may be more precise than prose for state machines, schemas, or types. Use them sparingly.

## Testing decisions

- Primary test seam: <module name> (cited at interface level)
- Mocking strategy: <at system boundaries only — see /keep:tdd>
- Regression coverage: <behaviours that must not break>

## Out of scope

- <Explicitly excluded things>
- <Things deferred to future PRDs>

## Pointers

- Plan source: this conversation (cite the grilling outcome if applicable)
- Related ADRs: `docs/adr/NNNN-*.md` (if any)
- Prior decisions: `mcp__mind__search "<topic>"`
```

**Rules:**

- **No file paths in the body.** Use module names and seam names. Paths rot in weeks; names survive refactors.
- **User stories are exhaustive.** Better to over-enumerate than to under-enumerate — each story becomes a candidate issue in `/keep:to-issues`.
- **Implementation decisions are constraints, not explorations.** They were settled in the conversation. Reopening happens in a new PRD, not by editing this one.
- **Out of scope is load-bearing.** Future-you needs to know what *not* to do.

### Phase 4 — Publish

**Approval gate scales with tracker blast radius** (per `rules/core.md` Tier 2):

| Tracker | Reversibility | Gate |
|---------|---------------|------|
| **GitHub / Linear** | Irreversible public action (`ready-for-agent` label signals agents may auto-pick this work) | **Full Tier 2**: user approved the PRD body **and** confirmed the `ready-for-agent` label is wanted |
| **local** (`.issues/<slug>.md`) | Fully reversible — just edit the file | **Lightweight**: confirm the file path and body with the user, then write |

Match the gate to the tracker detected in Phase 2. Don't apply the heavyweight GitHub gate to a local-file write — it's ceremony. Don't skip the gate on GitHub because "it's just an issue" — issues are public and signal agents.

| Tracker | Action |
|---------|--------|
| GitHub | `gh issue create --title "<title>" --body "$(cat .issues/<slug>.md)" --label "ready-for-agent"` |
| Linear | Linear CLI: create issue with the body |
| local | Write to `.issues/<slug>.md` and confirm |

Then:

- [ ] Echo the issue URL or path to the user
- [ ] Run `/keep:ubiquitous-language` if the conversation surfaced new domain terms (capture them now while context is fresh)
- [ ] Suggest next step: `/keep:to-issues` to break this PRD into independently-grabbable slices

## Anti-Patterns

- ❌ **Interviewing the user.** This skill synthesizes; `/keep:grilling` interviews. If the plan isn't locked, route there.
- ❌ **File paths in the body.** They rot. Use module names.
- ❌ **Implementation details.** The PRD says *what* and *why*, not *how*. *How* lives in `/keep:to-issues` and the eventual commits.
- ❌ **Vague user stories.** "As a user, I want the app to be better" is not a story. Each story must have a testable acceptance criterion implied.
- ❌ **Skipping "Out of scope".** Without it, scope creep is inevitable.
- ❌ **Specifying multiple primary test seams.** If you need 3+ seams, the design needs prefactor work first — note it as a prerequisite.

## Resource Check

| Resource | How to check | Degraded mode |
|----------|-------------|---------------|
| `git` | `git rev-parse --is-inside-work-tree` | Skip git log context; warn user |
| `mind` | `mcp__mind__search` available | Skip "prior decisions" pointer |
| `gh` | `command -v gh && gh auth status` | Fall back to local `.issues/` |

## Composability

- **Input ← grilling (deep)**: a deep grilling session produces locked decisions and sharpened terminology — exactly what a PRD needs.
- **Output → to-issues**: PRD becomes the input for `/keep:to-issues` (vertical-slice decomposition).
- **Output → ubiquitous-language**: any new terms land in the glossary now, not later.
- **Output → sprint**: a ready-for-agent PRD is the ideal sprint input — Phase 1 (Research) reads it.
- **Output → loop**: a PRD published to GitHub with `ready-for-agent` label is a perfect loop discovery source.
