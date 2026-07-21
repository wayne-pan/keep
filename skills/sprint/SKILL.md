---
name: keep:sprint
version: "1.4"
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
| 1 | Research | Findings in `.sprint/RESEARCH.md`, gaps documented | `references/context-engineering.md` |
| 2 | Plan | Structured `PLAN.md` written to temp dir (Task/Step/Interfaces); user approves | Design It Twice + Plan Document below |
| 3 | Implement | All planned modules pass validation ladder | `references/validation-ladder.md`, `references/subagent-strategy.md` |
| 4 | Quality Gate | Format → Build → Test → Lint all pass | table below |
| 5 | Review | `/keep:review` findings addressed or deferred | `/keep:review` skill |
| 6 | Test | Full test suite + build + lint all pass | inline |
| 7 | Ship | Commit landed (**ask before push**) | inline |
| 8 | Reflect | FINDINGS.md + memory updated; `/keep:cross-review` offered if other agents available | inline |

Skip phases 1-2 only for trivial tasks (1 file, <5 lines).

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
- **Plan→Implement**: user approved the written PLAN.md; every task has Files / Interfaces / Steps; test plan defined; **atomicity** (each change = one sentence without "and"); **scope** (5+ files → warn, consider splitting)
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

After Design It Twice, write a structured PLAN.md to the **temp dir** (never the project tree — keeps git status clean). Plan artifacts are session-scoped and disposable.

```bash
# One-time per sprint: create session plan dir + anchor
sprint-plan init

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
- **Self-review before approval**: scan for placeholder patterns, verify each spec requirement maps to a task, check type consistency across tasks.

**Approval gate**: present the written PLAN.md path to the user; do not enter Implement until they approve.

**Cross-platform temp dir**: `sprint-plan` honors `KEEP_SPRINT_TMP > TMPDIR > TEMP > TMP > /tmp` — works on Linux, macOS, Windows-native bash, Git Bash, Cygwin. The chosen path is anchored in `.sprint/PLAN_TMP_PATH` so sibling commands rediscover it after `cd` shifts.

**Cleanup**: `sprint-plan clear` at Ship phase (after Reflect). Removes the temp dir + anchor file.

## State Management (Disk-Driven)

Two distinct locations, two distinct lifecycles — don't conflate them:

| Location | Purpose | Lifecycle |
|----------|---------|-----------|
| `.sprint/` (project) | Phase state, decisions, knowledge | Per-sprint, deleted at Ship (preserve KNOWLEDGE/FINDINGS) |
| Temp dir (`sprint-plan path`) | PLAN.md, task briefs, reports, review packages | Per-sprint, cleared at Ship |

`.sprint/` is the source of truth for **state** — context compaction is safe. The temp dir holds **plan artifacts** that subagents consume as files (not pasted text). Full schemas and lifecycle: `references/state-machine.md`.

| File | Location | Purpose |
|------|----------|---------|
| `STATE.yaml` | `.sprint/` | Phase, progress, recent actions |
| `RESEARCH.md` | `.sprint/` | Compressed research findings |
| `DECISIONS.md` | `.sprint/` | Architecture decisions + rationale |
| `KNOWLEDGE.md` | `.sprint/` | Project knowledge (append-only, cross-sprint) |
| `FINDINGS.md` | `.sprint/` | Cross-session insights (append-only, cross-sprint) |
| `CHECKPOINT.yaml` | `.sprint/` | Phase transition checkpoint |
| `PLAN_TMP_PATH` | `.sprint/` | Anchor: absolute path to session's temp plan dir |
| `PLAN.md` | temp dir | Structured implementation plan (Phase 2 output) |
| `task-N-brief.md` | temp dir | Per-task slice subagents read instead of full plan |
| `task-N-report.md` | temp dir | Per-task implementer report |
| `review-*.md` | temp dir | Diff packages for reviewer subagents |

```bash
sprint-checkpoint save <phase> <step>     # at each phase transition
sprint-checkpoint resume                  # on sprint start
sprint-plan init                          # at Plan phase start
sprint-plan write-plan << 'EOF' ... EOF   # after Design It Twice
sprint-plan task-brief <N>                # before dispatching task N implementer
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

**Stuck detection** (track `recent_actions` in STATE.yaml): same error 2+ times → `.sprint/STUCK.md`, try alternative. Loop pattern → stop. No progress after 3 iterations → suggest fresh context.

**Fork recursion guard.** Subagents spawning subagents must have a depth limit (max 2 levels). Without guard: exponential context cost, timeout cascades, stale references. Pattern: pass `--max-depth N` or check parent context before delegating.

## References

- `references/state-machine.md` — full state file schemas and lifecycle
- `references/validation-ladder.md` — validation commands and auto-fix protocol
- `references/context-engineering.md` — context budget, hygiene, task management
- `references/subagent-strategy.md` — subagent orchestration patterns
- `references/anti-rationalizations.md` — rationalization traps
