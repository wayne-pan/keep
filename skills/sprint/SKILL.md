---
name: keep:sprint
version: "1.5"
triggers: ["/keep:sprint", "/keep:build feature", "/keep:ship feature", "/keep:implement feature", "/keep:add feature", "/keep:new module"]
routes_to: ["review"]
description: >
  Full sprint workflow orchestration. TRIGGER when: the user asks to build a feature,
  run a sprint, ship something, implement, create a new module, add a feature, or says
  /keep:sprint. Runs the complete Research → Plan → Implement → Quality Gate → Review
  → Test → Ship → Reflect cycle using Claude Code subagents for parallel execution.
  Do NOT trigger for: quick questions, single-file edits, research tasks, or skill
  creation (use /keep:skill-forge).
resources: ['git', 'subagents', 'mind', 'architecture-language']
---

# Sprint Workflow (RPI)

Structured development sprint: Research → Plan → Implement → Quality Gate → Review → Test → Ship → Reflect.

## Phase Map

| # | Phase | Done when | Detail |
|---|-------|-----------|--------|
| 1 | Research | Task dir created (`sprint-plan init <slug>`), findings in `.sprint/<task>/RESEARCH.md`, gaps documented | `references/context-engineering.md` |
| 2 | Plan | Structured `PLAN.md` written to `.sprint/<task>/` (Task/Step/Interfaces); plan-review sub-agent passes | Design It Twice + Plan Review Gate + Plan Document below |
| 3 | Implement | All planned modules pass validation ladder | `references/validation-ladder.md`, `references/subagent-strategy.md` |
| 4 | Quality Gate | Format → Build → Test → Lint all pass | table below |
| 5 | Review | `/keep:review` findings addressed or deferred | `/keep:review` skill |
| 6 | Test | Full test suite + build + lint all pass | inline |
| 7 | Ship | Commit landed (**ask before push**) | inline |
| 8 | Reflect | FINDINGS.md + memory updated | inline |

Skip phases 1-2 only for trivial tasks (1 file, <5 lines).

**Phase Boundary Protocol** (every phase transition): `sprint-checkpoint save <phase> <step>` → summarize phase outcome into the task dir's `STATE.yaml` (`$(sprint-plan path)/STATE.yaml`) → auto-enter next phase. Context pressure never pauses the sprint for a window switch — `.sprint/` is disk-backed and compaction-safe; after any compaction, re-read `STATE.yaml` and continue from the recorded step.

**Sprint start (before Research)**: `sprint-plan init <task-slug>` — derive the slug from the feature name (e.g. `dry-run-flag`). Creates `.sprint/<task-slug>/` + anchors it in `.sprint/CURRENT`. One task = one directory: different sprints never overwrite each other's PLAN.md/STATE.yaml. Re-running `init` with an existing name resumes that task with all state intact.

## Resource Check (Research start)

| Resource | How to check |
|----------|-------------|
| `git` | `git rev-parse --is-inside-work-tree` |
| `subagents` | Agent tool available (always true) |
| `mind` | `mcp__mind__search` available |
| `git-diff` | `git diff --name-only HEAD~1` returns data |
| `settings-json` | `.claude/settings*.json` exists |

Missing → warn user, proceed in degraded mode.

## Auto-routing (Research start)

Match user's original request, pre-activate sub-skills:

| Keyword | Pre-activate |
|---------|--------------|
| "review", "audit", "check code" | `/keep:review` at Review phase |
| "refactor", "restructure" | Blast radius analysis mandatory |
| "security", "vulnerability" | Security-focused review subagent |
| "test", "coverage", "TDD" | Test phase gets extra weight |
| "learnings", "patterns" | `dream_cycle` at Reflect phase |

## Quality Gate (Phase 4)

Multi-stage. Each stage must pass before next. Failure → back to Implement.

| Stage | Command |
|-------|---------|
| Format | `bash ~/.claude/hooks/auto-format.sh <changed-file>` |
| Build | `make` or `npm run build` (auto-detect) |
| Test | `make test` or `npm test` (auto-detect) |
| Lint | `npm run lint` or project linter |

Checkpoint: `sprint-checkpoint save quality-gate <stage>` at each stage transition.

## Phase Guards

Before entering next phase, verify:

- **Research→Plan**: critical files read; unknowns documented; RESEARCH.md written
- **Plan→Implement**: plan-review sub-agent passed PLAN.md (verdict logged in `.sprint/<task>/STATE.yaml`); every task has Files / Interfaces / Steps; test plan defined; **atomicity** (each change = one sentence without "and"); **scope** (5+ files → warn, consider splitting)
- **Implement→Review**: Quality Gate passed; no incomplete markers in changed code; validation ladder passed for every file
- **Review→Test**: review findings addressed; no unresolved critical/high severity issues

## Shortcuts

| User says | Action |
|-----------|--------|
| `/keep:sprint` | Full Research → Ship cycle |
| `/keep:sprint build` | Skip Research + Plan, go to Implement |
| `/keep:sprint ship` | Skip to Ship |
| `/keep:sprint test` | Run Test phase only |
| "just ship it" | Implement → Review → Test → Ship |

## Design It Twice (Plan phase)

For new modules, cross-cutting refactors, or 3+ file plans. Skip for trivial changes.

Spawn 3 parallel sub-agents with constraints: (1) minimize interface — 1-3 entry points, (2) maximise flexibility — many use cases, (3) optimise for the most common caller. Each outputs: signature, usage example, what it hides, trade-offs. Compare on depth, locality, seam placement, testability. **Give strong recommendation, not a menu** — propose hybrid if elements combine well.

Uses vocabulary from `rules/architecture-language.md`: module, interface, seam, adapter, depth, leverage, locality.

## Plan Document (Phase 2 output)

After Design It Twice, write a structured PLAN.md to the **task dir** (`.sprint/<task>/` — gitignored, one dir per task, disposable at Ship).

```bash
# At sprint start (before Research) — create the per-task dir + anchor:
sprint-plan init <task-slug>

# Write PLAN.md from your drafted content
sprint-plan write-plan << 'EOF'
<structured plan content>
EOF
```

**PLAN.md structure:**

```markdown
# <Feature> Implementation Plan

**Goal:** <one sentence>
**Architecture:** <2-3 sentences>
**Tech Stack:** <key libs/versions>

## Global Constraints
- <verbatim from spec — version floors, naming rules, platform requirements>

## Task 1: <component>

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/existing.py:123-145`
- Test: `tests/exact/path/test.py`

**Interfaces:**
- Consumes: <exact signatures from earlier tasks>
- Produces: <exact signatures later tasks rely on>

**Steps:**
- [ ] Write failing test (paste actual code)
- [ ] Run `pytest tests/path/test.py::test_name -v`, expect FAIL
- [ ] Implement minimal code (paste actual code)
- [ ] Run `pytest tests/path/test.py::test_name -v`, expect PASS
- [ ] Commit: `git commit -m "feat: ..."`

## Task 2: <component>
...
```

**Rules:**
- **No placeholders.** Every step shows actual code or commands. "TBD" / "implement later" / "similar to Task N" = plan failure.
- **Exact file paths with line ranges** for modifications.
- **Consumes/Produces blocks** are how downstream task subagents learn upstream signatures — they only read their own brief, not the full PLAN.md.

## Plan Review Gate (Phase 2 → Implement)

After writing PLAN.md, spawn **1 fresh sub-agent** (different context — not the coordinator) to adversarially review the plan before entering Implement. **No user approval needed** — review pass replaces approval.

**Sub-agent brief** — read PLAN.md at `sprint-plan path` and check:
- **Placeholders**: no "TBD" / "implement later" / "similar to Task N"
- **Spec coverage**: every requirement from RESEARCH.md maps to a Task
- **Type consistency**: Consumes/Produces signatures match across tasks
- **Atomicity**: each Step is one sentence without "and"
- **Exact paths**: every modification has file:line-range
- **Test plan**: each Task has a failing-test step
- **Scope**: 5+ files → flag for split consideration

**Output**: `pass` OR `fail` with a numbered list (each item: file/section + what's wrong + concrete fix).

**Flow**:
- `pass` → log `plan_review: pass` to `.sprint/<task>/STATE.yaml`, auto-enter Implement.
- `fail` → Claude applies each fix directly to PLAN.md, re-spawns a fresh review sub-agent. **Max 2 rounds**; still failing → STOP, present PLAN.md + remaining findings to user.

**Anti-rationalization**: the coordinator reviewing its own plan does not count — self-approval is the trap this gate exists to break. The sub-agent must be fresh (no shared context with the planner).

**Cleanup**: `sprint-plan clear` at Ship phase (after Reflect). Removes the active task dir + anchor file.

## State Management (Disk-Driven, Per-Task)

Everything lives under `.sprint/` — one root, two scopes:

| Scope | Path | Holds | Lifecycle |
|-------|------|-------|-----------|
| Per-task | `.sprint/<task>/` | STATE.yaml, RESEARCH.md, DECISIONS.md, CHECKPOINT.yaml, PLAN.md, briefs, reports, review packages | Created at sprint start, deleted at Ship |
| Cross-sprint | `.sprint/` root | KNOWLEDGE.md, FINDINGS.md, CODE_MAP.md, CURRENT anchor | Persists across sprints |

One task = one directory — two sprints in the same repo never overwrite each other. `.sprint/` is gitignored and disk-backed, so context compaction is safe. Subagents consume plan artifacts as files (not pasted text). Full schemas and lifecycle: `references/state-machine.md`.

| File | Location | Purpose |
|------|----------|---------|
| `CURRENT` | `.sprint/` root | Anchor: name of the active task |
| `STATE.yaml` | task dir | Phase, progress, recent actions |
| `RESEARCH.md` | task dir | Compressed research findings |
| `DECISIONS.md` | task dir | Architecture decisions + rationale |
| `KNOWLEDGE.md` | `.sprint/` root | Project knowledge (append-only, cross-sprint) |
| `FINDINGS.md` | `.sprint/` root | Cross-session insights (append-only, cross-sprint) |
| `CHECKPOINT.yaml` | task dir | Phase transition checkpoint |
| `PLAN.md` | task dir | Structured implementation plan (Phase 2 output) |
| `task-N-brief.md` | task dir | Per-task slice subagents read instead of full plan |
| `task-N-report.md` | task dir | Per-task implementer report |
| `review-*.md` | task dir | Diff packages for reviewer subagents |

```bash
sprint-plan init <task-slug>               # at sprint start (before Research)
sprint-checkpoint save <phase> <step>     # at each phase transition
sprint-checkpoint resume                  # on sprint start
sprint-plan write-plan << 'EOF' ... EOF   # after Design It Twice
sprint-plan task-brief <N>                # before dispatching task N implementer
sprint-plan list                          # see all task dirs (active marked)
sprint-plan clear                         # at Ship phase (after Reflect)
```

KV store: `kv-set`/`kv-get` shares artifacts between subagents; `kv-clear` at completion.

## Safety

- **Ask before destructive ops** (force push, drop table, rm -rf)
- **Never push to main/master** without explicit approval
- **Two same-type failures** → STOP, ask user
- **Loop pattern** (A→B→A→B) → STOP, present diagnosis

**Cooperative Stop Event**: `safety-guard.sh` writes `/tmp/keep-stop-{SESSION_ID}` on CRITICAL violations. Check at each phase transition (30s grace for running subagents):

```bash
SESSION_ID=$(cat .sprint/SESSION_ID 2>/dev/null || echo "default")
[ -f "/tmp/keep-stop-${SESSION_ID}" ] && { echo "STOP: $(cat /tmp/keep-stop-${SESSION_ID})"; rm -f "/tmp/keep-stop-${SESSION_ID}"; }
```

**Stuck detection** (track `recent_actions` in STATE.yaml): same error 2+ times → `.sprint/<task>/STUCK.md`, try alternative. Loop pattern → stop. No progress after 3 iterations → suggest fresh context.

**Fork recursion guard.** Subagents spawning subagents must have a depth limit (max 2 levels). Without guard: exponential context cost, timeout cascades, stale references. Pattern: pass `--max-depth N` or check parent context before delegating.

## References

- `references/state-machine.md` — full state file schemas and lifecycle
- `references/validation-ladder.md` — validation commands and auto-fix protocol
- `references/context-engineering.md` — context budget, hygiene, task management
- `references/subagent-strategy.md` — subagent orchestration patterns
- `references/anti-rationalizations.md` — rationalization traps
