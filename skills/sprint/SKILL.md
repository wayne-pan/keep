---
name: keep:sprint
version: "1.3"
triggers: ["/keep:sprint", "/keep:build feature", "/keep:ship feature", "/keep:implement feature", "/keep:add feature", "/keep:new module"]
routes_to: ["review"]
description: >
  Full sprint workflow orchestration. TRIGGER when: the user asks to build a feature,
  run a sprint, ship something, implement, create a new module, add a feature, or says
  /keep:sprint. Runs the complete Research → Plan → Implement cycle using Claude Code
  subagents for parallel execution. Do NOT trigger for: quick questions, single-file
  edits, research tasks, or skill creation (use /keep:skill-forge).
resources: ['git', 'subagents', 'mind', 'architecture-language']
---

# Sprint Workflow (RPI)

Structured development sprint: Research → Plan → Implement → Verify → Ship → Reflect.
**Compress context at every phase boundary to stay in the smart zone.**

## Phase Map

| # | Phase | Done when | Detail |
|---|-------|-----------|--------|
| 1 | Research | Findings in `.sprint/RESEARCH.md`, gaps documented | `references/context-engineering.md` |
| 2 | Plan | Files listed with line ranges; user approves plan | Design It Twice below |
| 3 | Implement | All planned modules pass validation ladder | `references/validation-ladder.md`, `references/subagent-strategy.md` |
| 4 | Quality Gate | Format → Build → Test → Lint all pass | table below |
| 5 | Review | `/keep:review` findings addressed or deferred | `/keep:review` skill |
| 6 | Test | Full test suite + build + lint all pass | inline |
| 7 | Ship | Commit landed (**ask before push**) | inline |
| 8 | Reflect | FINDINGS.md + memory updated | inline |

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

Checkpoint: `sprint-checkpoint save quality-gate <stage>` at each stage boundary.

## Phase Guards

Before entering next phase, verify:

- **Research→Plan**: critical files read; unknowns documented; RESEARCH.md written
- **Plan→Implement**: user approved plan; target files listed with line ranges; test plan defined; confidence levels assigned; **atomicity** (each change = one sentence without "and"); **scope** (5+ files → warn, consider splitting)
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

## State Management (Disk-Driven)

`.sprint/` is the source of truth — context compaction is safe. Full schemas and lifecycle: `references/state-machine.md`.

| File | Purpose |
|------|---------|
| `STATE.yaml` | Phase, progress, recent actions |
| `RESEARCH.md` | Compressed research findings |
| `DECISIONS.md` | Architecture decisions + rationale |
| `KNOWLEDGE.md` | Project knowledge (append-only, cross-sprint) |
| `FINDINGS.md` | Cross-session insights (append-only, cross-sprint) |
| `CHECKPOINT.yaml` | Phase boundary checkpoint |

Lifecycle: create at Research start → update every phase → delete at Ship (preserve KNOWLEDGE.md, FINDINGS.md).

```bash
sprint-checkpoint save <phase> <step>     # at each phase boundary
sprint-checkpoint resume                  # on sprint start
```

KV store: `kv-set`/`kv-get` shares artifacts between subagents; `kv-clear` at completion.

## Safety

- **Ask before destructive ops** (force push, drop table, rm -rf)
- **Never push to main/master** without explicit approval
- **Two same-type failures** → STOP, ask user
- **Loop pattern** (A→B→A→B) → STOP, present diagnosis

**Cooperative Stop Event**: `safety-guard.sh` writes `/tmp/keep-stop-{SESSION_ID}` on CRITICAL violations. Check at each phase boundary (30s grace for running subagents):

```bash
SESSION_ID=$(cat .sprint/SESSION_ID 2>/dev/null || echo "default")
[ -f "/tmp/keep-stop-${SESSION_ID}" ] && { echo "STOP: $(cat /tmp/keep-stop-${SESSION_ID})"; rm -f "/tmp/keep-stop-${SESSION_ID}"; }
```

**Stuck detection** (track `recent_actions` in STATE.yaml): same error 2+ times → `.sprint/STUCK.md`, try alternative. Loop pattern → stop. No progress after 3 iterations → suggest fresh context.

## References

- `references/state-machine.md` — full state file schemas and lifecycle
- `references/validation-ladder.md` — validation commands and auto-fix protocol
- `references/context-engineering.md` — context budget, hygiene, task management
- `references/subagent-strategy.md` — subagent orchestration patterns
- `references/anti-rationalizations.md` — rationalization traps
