---
name: keep:triage
version: "1.0"
triggers: ["/keep:triage", "/keep:triage issues", "/keep:inbox review", "/keep:sort issues", "/keep:issue state machine"]
routes_to: ["to-issues", "diagnosing-bugs", "tdd"]
description: >
  Move incoming issues (bugs, requests, findings) through a triage state machine:
  raw → triaged → assigned → in_progress → review → done (or: won't_fix / duplicate /
  blocked). TRIGGER when: user says "/keep:triage", "triage my inbox", "sort these
  issues", or has a backlog of unsorted items from external sources (user reports,
  review findings, /keep:review output, /keep:architecture-scan candidates that
  became issues). Detects issue tracker (gh CLI / .issues/ / Linear) and adapts.
  Do NOT trigger for: issues you just created via /keep:to-issues (those are
  already agent-ready — no triage needed), or single-issue quick actions.
resources: ['git', 'mind']
---

# Triage

Move issues from external sources through a state machine until each is either **done**, **won't_fix**, **duplicate**, or **blocked** with a named blocker. Triage is the discipline that prevents a backlog from becoming a swamp.

**Key distinction from `/keep:to-issues`**: `to-issues` *creates* agent-ready slices from a plan you authored. `triage` *processes* issues from sources you didn't author (user reports, review findings, external requests). Triage output may feed into `to-issues` if an item needs decomposition.

## State Machine

```
                  ┌──────────────────────────────────────┐
                  │                                      ▼
  raw ──► triaged ──► assigned ──► in_progress ──► review ──► done
            │            │              │             │
            │            │              │             ├──► won't_fix
            │            │              │             ├──► duplicate
            │            │              │             └──► blocked
            │            │              │
            └────────────┴──────────────┴──► won't_fix / duplicate / blocked
                                              (any state can exit early)
```

| State | Meaning | Required to leave |
|-------|---------|-------------------|
| `raw` | Unread, freshly imported | Has been read once |
| `triaged` | Categorised: bug / feature / question / cleanup; priority set | Has an assignee (or explicitly `unassigned` by choice) |
| `assigned` | Owner identified | Owner has started (commit, comment, status change) |
| `in_progress` | Active work | PR opened or implementation visible |
| `review` | PR open or handed to `/keep:review` | Review verdict |
| `done` | Merged / resolved / answered | Reason recorded (per hard rule below) |
| `won't_fix` | Explicit decision not to do it | Reason recorded |
| `duplicate` | Points to another issue | Original issue referenced |
| `blocked` | Cannot proceed | Blocker named (person, decision, external dependency) |

**Hard rule**: every exit state (`done` / `won't_fix` / `duplicate` / `blocked`) must have a recorded reason. "Closed without comment" is not triage — it's abandonment.

## Workflow

### Phase 1 — Gather inbox

Detect issue tracker:

```bash
gh repo view --json nameWithOwner 2>/dev/null   # GitHub
[ -d ".issues" ] && echo "local"                 # local
command -v linear || command -v linear-cli                            # Linear (binary name varies by version)
```

Collect `raw` issues:

| Source | Query |
|--------|-------|
| GitHub | `gh issue list --state open --label "inbox"` (or unlabeled) |
| local | `ls .issues/*.md` and grep for `Status: raw` (or absence of status) |
| Linear | Linear CLI: list issues in Inbox |

Also pull from in-repo sources:

- `/keep:review` output saved to `.review/FINDINGS.md` — each finding becomes a candidate issue
- `/keep:architecture-scan` report `.architecture-scan/REPORT.md` — Strong/Worth-exploring candidates
- `/keep:diagnosing-bugs` post-mortem notes (if any recommended follow-up issues)

**Done when:**

- [ ] Inbox collected into a single list with source + ID + title + current state
- [ ] `mcp__mind__search "triage-history"` checked for prior decisions on the same topics (avoid re-deciding)

### Phase 2 — Triage each item

For each `raw` item, decide:

#### 2a. Category (pick one)

| Category | Marker | Hand-off |
|----------|--------|----------|
| `bug` | Behaviour contradicts intent | `/keep:diagnosing-bugs` |
| `feature` | New capability | `/keep:to-prd` if large, direct `/keep:to-issues` if small |
| `question` | Needs answer, not code | Answer inline, mark `done` |
| `cleanup` | Refactor / slop / naming | `/keep:deslop` or `/keep:architecture-scan` |
| `infra` | Build / CI / deploy / config | Direct work or `/keep:harness` if keep-internal |

#### 2b. Priority (pick one)

| Priority | Criteria |
|----------|----------|
| `P0` | Blocks current sprint OR active user-facing outage |
| `P1` | Affects users or blocks near-term work |
| `P2` | Should do this quarter |
| `P3` | Backlog — nice to have |

When unsure between two priorities, pick the lower one. Triage optimism is a known failure mode.

#### 2c. Size (pick one)

| Size | Means |
|------|-------|
| `xs` | One slice, one session — direct `/keep:tdd` |
| `s` | One vertical slice via `/keep:to-issues` |
| `m` | 2-3 slices — `/keep:to-prd` then `/keep:to-issues` |
| `l` | Multi-PRD — split into multiple `m` items first |

#### 2d. Decomposition check

If `size > s`, the item needs decomposition before it can be `assigned`. Either:

- Split into N child issues right now (use `/keep:to-issues`), or
- Defer: mark `blocked` by `needs-decomposition` and create a single "Decompose <X>" tracking issue.

#### 2e. Duplicate check

Before finalising:

- `mcp__mind__search "<topic>"` for prior resolutions
- `gh issue list --search "<similar terms>"` (GitHub) or equivalent
- If duplicate: mark `duplicate`, reference the canonical issue, do not re-triage.

**Done when:**

- [ ] Every item has category + priority + size
- [ ] Duplicates marked
- [ ] Items needing decomposition are identified

### Phase 3 — Assignment

For each `triaged` item:

- If `size ≤ s` and clear owner → assign, move to `assigned`
- If `size > s` → route through `/keep:to-issues` first
- If unclear owner → leave `assigned: unassigned`, surface in summary

**Done when:**

- [ ] Every `s`/`xs` item has an assignee or explicit `unassigned`
- [ ] Every `m`/`l` item has a decomposition plan or `blocked` marker

### Phase 4 — Sync to tracker

**Tier 2 approval gate** (per `rules/core.md`): state changes are network mutations and issue closures are irreversible public actions.

- [ ] User approved the proposed label/assignee/closure changes (present them as a diff-style summary first, then execute the writes below)

| Tracker | Action |
|---------|--------|
| GitHub | `gh issue edit <id> --add-label "<category>,P<priority>,<size>"` ; `gh issue edit <id> --add-assignee "@<owner>"` |
| local | Edit `.issues/<slug>.md` frontmatter: `status: <state>`, `category: <c>`, `priority: P<n>`, `size: <sz>`, `assignee: <owner>` |
| Linear | Linear CLI update |

For exits:

- `won't_fix` → comment with reason, close
- `duplicate` → comment with canonical issue reference, close
- `blocked` → comment with blocker name, leave open

### Phase 5 — Summary and persistence

Output a summary table:

```
Triage summary (N items):
  done:        X
  in_progress: Y
  assigned:    Z
  triaged:     W (ready for pickup)
  blocked:     V
  won't_fix:   U
  duplicate:   T

Top 3 next pickups (by priority):
  1. #42 (P0, bug, xs) — "Refund double-charges users" → /keep:diagnosing-bugs
  2. #38 (P1, feature, s) — "Export orders as CSV" → /keep:tdd
  3. #45 (P1, cleanup, s) — "Rename Fulfillment→Shipment" → /keep:ubiquitous-language

Decomposition needed:
  - #41 (P1, feature, l) — "Multi-currency support" → /keep:to-prd

Blocked:
  - #39 blocked by: legal-review (decision needed from @legal-team)
```

Then:

- [ ] `mcp__mind__remember` the triage decisions (categories, priorities, exits) so the next triage doesn't re-decide them
- [ ] Echo the summary to the user

## Anti-Patterns

- ❌ **Triage optimism.** "Looks small, mark it `xs`" when you haven't read the code. Verify size with a quick `Grep` / `Glob`.
- ❌ **Skipping the duplicate check.** Most backlogs have 30% duplicates. Always search before assigning.
- ❌ **`won't_fix` without a reason.** Future-you will reopen it. Always record why.
- ❌ **`blocked` without a name.** "Blocked" by what? Name the person, decision, or external dependency.
- ❌ **Triage on items you just created.** `/keep:to-issues` output is already triaged — don't double-process.
- ❌ **Closing without comment.** That's abandonment, not triage.

## Resource Check

| Resource | How to check | Degraded mode |
|----------|-------------|---------------|
| `git` | Repo is git | Skip `gh` detection; fall back to local `.issues/` |
| `mind` | `mcp__mind__search` available | Skip duplicate / history check — higher risk of re-deciding |
| `gh` | `command -v gh && gh auth status` | Fall back to local |

## Composability

- **Input ← review**: `/keep:review` findings feed here as `raw` items.
- **Input ← architecture-scan**: Strong/Worth-exploring candidates feed here as `raw` cleanup items.
- **Input ← diagnosing-bugs**: post-mortem follow-ups feed here.
- **Output → to-issues**: `size > s` items decomposed into vertical slices.
- **Output → tdd / sprint**: `size ≤ s` items picked up directly.
- **Output → loop**: triaged `ready-for-agent` issues are loop discovery fuel.
- **Differs from to-issues**: triage processes *external* input; to-issues decomposes *your own* plan.
