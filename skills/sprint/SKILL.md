---
name: keep:sprint
version: "1.2"
triggers: ["/keep:sprint", "/keep:build a feature", "/keep:implement", "/keep:ship", "/keep:make", "/keep:create", "/keep:add feature", "/keep:develop", "/keep:write", "/keep:new module", "/keep:new file"]
routes_to: ["review"]
description: >
  Full sprint workflow orchestration. TRIGGER when: the user asks to build a feature,
  run a sprint, ship something, make something, implement, create a new module, add
  a feature, or says /keep:sprint. Runs the complete Research → Plan → Implement cycle
  using Claude Code subagents for parallel execution. Do NOT trigger for: quick
  questions, single-file edits, or research tasks.
resources: ['git', 'subagents', 'mind', 'architecture-language']
---

# Sprint Workflow (RPI)

A structured development sprint based on Research-Plan-Implement methodology.
Core principle: **compress context at every phase boundary to stay in the smart zone**.

## Phase Overview

### 1. Research
Understand the system as it actually is — code is truth, docs lie.

**Resource Check** — verify required resources before starting:
| Resource | How to check |
|----------|-------------|
| `git` | `git rev-parse --is-inside-work-tree` |
| `subagents` | Agent tool available (always true in Claude Code) |
| `mind` | `mcp__mind__search` tool available |
| `git-diff` | `git diff --name-only HEAD~1` returns data |
| `settings-json` | `.claude/settings.json` or `.claude/settings.local.json` exists |
If any resource missing → warn user, proceed with degraded mode (skip features requiring missing resource).

**Git Memory** — before exploring code, learn from recent history:
```bash
git log --oneline -10              # what was done recently
git diff HEAD~3..HEAD --stat       # scope of recent changes
git log --oneline --revert         # what failed and was reverted
```
Use git history to: avoid repeating failed approaches, understand what changed recently, find reverted experiments worth revisiting. Record insights in RESEARCH.md.

**Smart context selection** — match read strategy to file size:
| Size | Strategy |
|------|----------|
| <3KB | Full read |
| 3-10KB | `smart_outline` → `smart_unfold` relevant symbols |
| >10KB | `Grep` for specific patterns, never full read |

- Use subagents for exploration: "Return only file paths and key conclusions, under 200 words"
- **Discard raw output** — only keep conclusions in `.sprint/RESEARCH.md`

**Two-loop research architecture**:
1. **Inner loop**: Research a focused aspect → analyze findings
2. **Gap detection**: What's still unknown? What assumptions remain?
3. **Outer loop**: Synthesize all findings → if gaps remain, spawn new inner loop
4. **Terminate**: When no new gaps emerge OR 3 iterations reached

If trivial (1 file, <5 lines), skip to Implement.

**Auto-routing**: detect task keywords and pre-activate sub-skills:
| Keywords detected | Auto-activate |
|-------------------|---------------|
| "review", "/keep:audit", "/keep:check code" | `/keep:review` protocol at Review phase |
| "refactor", "/keep:restructure" | Blast radius analysis mandatory |
| "security", "/keep:vulnerability" | Security-focused review subagent |
| "test", "/keep:coverage", "/keep:TDD" | Test phase gets extra weight |
| "learnings", "/keep:patterns" | Run `dream_cycle` at Reflect phase |

Route by matching user's original request. No explicit user activation needed.

### 2. Plan
Lock architecture before writing code. A good plan lets the dumbest model execute correctly.

- Combine research with requirements
- List exact files to change with line ranges and code snippets
- Define test plan — **read test files before writing code**
- List security concerns and failure modes
- Confidence per change: high / medium (flag for user) / low (require approval)
- Record decisions in `.sprint/DECISIONS.md` with rationale

**Design It Twice** — for any non-trivial module design (new module, significant refactoring, or interface change):

1. **Frame the problem space**: write constraints, dependencies, and a rough sketch
2. **Spawn 3 parallel sub-agents** with different design constraints:
   | Agent | Constraint |
   |-------|-----------|
   | Agent 1 | "Minimize the interface — 1-3 entry points max" |
   | Agent 2 | "Maximise flexibility — support many use cases" |
   | Agent 3 | "Optimise for the most common caller" |
3. **Each sub-agent outputs**: interface signature, usage example, what it hides, trade-offs
4. **Compare on**: depth (leverage at interface), locality (where change concentrates), seam placement, testability
5. **Give strong recommendation**, not a menu — propose hybrid if elements from different designs combine well

Uses the vocabulary from `rules/architecture-language.md` — **module**, **interface**, **seam**, **adapter**, **depth**, **leverage**, **locality**.

Skip Design It Twice for trivial changes (single function, <5 lines). Always use it for new modules, cross-cutting refactors, or when the plan involves 3+ files.

Ask user to approve. **Review plans, not code.**

**Phase guard** (Research→Plan): Before entering Plan, verify:
- [ ] All critical files read and understood (no "I'll figure it out later")
- [ ] Unknowns documented with assumptions marked
- [ ] Research findings saved to `.sprint/RESEARCH.md`

### 3. Implement
Execute the plan with minimal context — stay in the smart zone.

| Scope | How |
|-------|-----|
| Single file, <50 lines | Claude Code directly |
| Multi-file refactor | Agent subagent per module |
| New module from scratch | Agent subagent with focused prompt |
| 3+ parallel subtasks | Multiple subagents in parallel |

Build rules:
- One module per subagent, always specify target files
- Sub-agents return structured JSON: `{"summary":"...", "/keep:confidence":0-1, "findings":[...], "deeper_question":null, "status":"done"}`
- Use KV store (`kv-set`/`kv-get`) for passing artifacts between sub-agents
- Respect recursion cap: `recursion-enter` before spawning children, `recursion-exit` after
- **Tests pass → Stop.** Do not refactor passing code
- After each subagent: discard raw output, keep only conclusions
- **Intentional compaction**: `/compact` at phase boundaries (Research→Plan, Plan→Implement, after milestone). NOT mid-edit. After compact: verify STATE.yaml survived.

**Validation ladder** (auto-enforced after each edit):
| File type | Check |
|-----------|-------|
| `.sh` | `bash -n <file>` |
| `.py` | `python3 -c "import ast; ast.parse(open(f).read())"` |
| `.js` | `node --check <file>` |
| `.json` | `python3 -m json.tool <file> > /dev/null` |
| Any | `git diff --stat` verify change scope |

After each module: run tests. If fail → auto-fix (1 retry), then escalate.

**Phase guard** (Plan→Implement): Before entering Implement, verify:
- [ ] Plan approved by user
- [ ] All target files listed with line ranges
- [ ] Test plan defined (read test files first)
- [ ] Confidence levels assigned per change
- [ ] **Atomicity**: each change describable in one sentence without "and" — if not, split
- [ ] **Scope check**: 5+ files in a single change triggers warning — consider splitting

### 4. Quality Gate
Multi-stage verification between Implement and Review. Each stage must pass before the next. Failure → back to Implement.

| Stage | Command | Failure action |
|-------|---------|----------------|
| Format | `auto-format.sh` on changed files | Auto-fix, re-check |
| Build | Project-specific (make, npm build, etc.) | Fix build errors |
| Test | Full test suite | Fix failing tests |
| Lint | Project linter | Fix lint errors |

```bash
# Auto-detect and run quality gate
CHANGED=$(git diff --name-only HEAD)
# Format stage
for f in $CHANGED; do bash ~/.claude/hooks/auto-format.sh "$f"; done
# Build stage (auto-detect)
[ -f Makefile ] && make || [ -f package.json ] && npm run build || true
# Test stage
[ -f Makefile ] && make test || [ -f package.json ] && npm test || true
# Lint stage
[ -f package.json ] && npm run lint 2>/dev/null || true
```

**Checkpoint**: `sprint-checkpoint save quality-gate <stage>` at each stage boundary.

### 5. Review
Use `/keep:review` protocol: spawn two subagents (bug hunter + security auditor), synthesize findings. Auto-fix obvious issues, flag complex ones for user.

**Phase guard** (Implement→Review): Before entering Review, verify:
- [ ] Quality Gate passed (all 4 stages)
- [ ] All planned changes implemented (no partial modules)
- [ ] Validation ladder passed for every modified file
- [ ] No TODO/FIXME placeholders remaining in changed code

### 6. Test
Prove it works before shipping. All via Bash — zero extra tokens.

- Run full test suite: auto-detect framework
- Run linter + build check
- If no tests exist, use subagent to create them

Gate: ALL tests must pass before Ship. If fail, back to Implement.

**Phase guard** (Review→Test): Before entering Test, verify:
- [ ] All review findings addressed (auto-fixed or explicitly deferred)
- [ ] No unresolved critical/high severity issues

### 7. Ship
- Review git diff one final time
- Commit with clear message from plan scope
- PR if applicable

Do NOT push to remote or merge without explicit user approval.

### 8. Reflect
- Summary (1-2 sentences), what went well / what didn't
- **Cost report**: estimate token usage (input + output tokens) and cost
- Capture lessons for `tasks/lessons.md`
- **Append findings**: key insights from this sprint → `FINDINGS.md` (cross-session knowledge)
- **Record to memory**: use `add_observation` for key discoveries, `dream_cycle(strengthen)` to update synthesis
- Clean up `.sprint/` directory (preserve KNOWLEDGE.md and FINDINGS.md)

## Shortcuts

| User says | What to do |
|-----------|-----------|
| `/keep:sprint` | Full Research → Ship cycle |
| `/keep:sprint build` | Skip Research + Plan, go straight to Implement |
| `/keep:sprint ship` | Skip to Ship |
| `/keep:sprint test` | Run Test phase only |
| "just ship it" | Implement → Review → Test → Ship |

## State Management (Disk-Driven)

The `.sprint/` directory is the source of truth. All state lives on disk — context compaction is safe.

| File | Purpose |
|------|---------|
| `STATE.yaml` | Current phase, progress, recent actions |
| `RESEARCH.md` | Compressed research findings |
| `DECISIONS.md` | Architecture decisions + rationale |
| `KNOWLEDGE.md` | Project knowledge (append-only, persists across sprints) |
| `FINDINGS.md` | Cross-session insights (append-only, persists across sprints) |
| `EXPERIMENTS.tsv` | Benchmark experiment log (iteration, metric, delta, status) |
| `TRIPLETS.jsonl` | Structured test triplets (state, action, reward) for regression tracking |

```yaml
# STATE.yaml schema
phase: research
iteration: 1
files_examined: []
files_modified: []
recent_actions: []    # last 5 actions for stuck detection
started: "2026-04-08T00:00:00Z"
last_update: "2026-04-08T00:05:00Z"
```

Lifecycle: create at Research start → update every phase → delete at Ship completion (keep KNOWLEDGE.md and FINDINGS.md).

### Checkpoint-Restart Protocol

At each phase boundary, save checkpoint state:
```bash
sprint-checkpoint save <phase> <step>
```

On sprint start, check for existing checkpoint:
```bash
resume=$(sprint-checkpoint resume)
if [ "$resume" != "none" ]; then
  # Offer user the choice to resume or start fresh
  echo "Existing checkpoint found: $resume"
fi
```

Checkpoint schema (`.sprint/CHECKPOINT.yaml`):
```yaml
phase: implement
step: "module-3"
files_modified: "file1.sh,file2.py"
timestamp: "2026-04-29T10:00:00Z"
remaining: [review, test, ship]
pending_decisions: []
```

### KV Store Lifecycle

The KV store provides shared state between sub-agents:
- **Setup**: KV store auto-initializes on first `kv-set` call (per session)
- **Usage**: Sub-agents write findings via `kv-set`, coordinator reads via `kv-get`
- **Teardown**: `kv-clear` at sprint completion (temp dir auto-cleaned on reboot)

## Safety

- Always ask before destructive operations (force push, drop table, rm -rf)
- Never push to main/master without explicit approval
- If a phase fails twice, STOP and ask for direction
- After 2 consecutive same-type failures: suggest trajectory reset (fresh context)

**Cooperative Stop Event** — cross-process safety coordination:
- safety-guard.sh sets `/tmp/keep-stop-{SESSION_ID}` on CRITICAL violations
- Sprint checks stop signal at each phase boundary:
  ```bash
  SESSION_ID=$(cat .sprint/SESSION_ID 2>/dev/null || echo "default")
  if [ -f "/tmp/keep-stop-${SESSION_ID}" ]; then
    echo "STOP: $(cat /tmp/keep-stop-${SESSION_ID})"
    rm -f "/tmp/keep-stop-${SESSION_ID}"
  fi
  ```
- Grace period: 30 seconds for running subagents to finish current work

**Stuck detection** — track `recent_actions` in STATE.yaml:
- **Same error 2+ times**: Write diagnosis to `.sprint/STUCK.md`, try alternative
- **Loop pattern** (A→B→A→B): Stop, present diagnosis, ask user for direction
- **No progress after 3 iterations**: Suggest fresh context window

## References

Deep-dive docs loaded on demand (read only when needed):
- `references/state-machine.md` — Full state file schemas and lifecycle
- `references/validation-ladder.md` — Detailed validation commands and auto-fix protocol
- `references/context-engineering.md` — Context budget, hygiene, task management
- `references/subagent-strategy.md` — Subagent orchestration patterns
- `references/anti-rationalizations.md` — Common rationalization traps
