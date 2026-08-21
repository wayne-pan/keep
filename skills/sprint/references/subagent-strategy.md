# Subagent Strategy Reference

Patterns for effective subagent orchestration.

## Core Principles

- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One task per subagent for focused execution

## Output Discipline

- **Output limit**: Tell subagents "Return only key conclusions and file paths, under 200 words"
- **Prefer structural tools**: Instruct subagents to use `smart_outline`/`smart_search` over full file reads
- After each subagent completes: discard raw output, keep only conclusions
- **Artifacts as files, not pasted text** — anything you paste into a dispatch stays resident in your context for the whole session. Pass file paths instead.

## Task Brief Discipline (Implement phase)

**Hard rule: a task implementer never reads the full PLAN.md.** The plan is the coordinator's contract with the user; the implementer gets a single-task slice.

### Why

A real plan runs 5-15k tokens. A subagent reading it (a) pollutes its context with sibling tasks it cannot affect, (b) gets anchored on global decisions outside its scope, (c) costs you re-reads on every re-dispatch. Slicing the plan into a per-task brief is the single biggest context savings available.

### How — file-based dispatch

```bash
# 1. Coordinator: extract the task slice into its own file
BRIEF=$(sprint-plan task-brief 3)          # writes <task-dir>/task-3-brief.md, prints path
REPORT=$(sprint-plan task-report 3)        # writes <task-dir>/task-3-report.md, prints path

# 2. Dispatch implementer with file paths + scene-setting (1-2 lines)
#    Do NOT paste plan content into the dispatch prompt.
```

**Implementer dispatch contract:**
- (a) One line on where this task fits in the project
- (b) The brief path: "read this first — it is your requirements, with exact values to use verbatim"
- (c) Cross-task interfaces the brief cannot know (resolutions to ambiguities you noticed)
- (d) The report path: "write your full report here; return only status + commits + one-line test summary + concerns"
- (e) Status vocabulary: `DONE` / `DONE_WITH_CONCERNS` / `NEEDS_CONTEXT` / `BLOCKED`

**Reviewer dispatch contract** (after implementer reports DONE):
```bash
BASE=<commit before implementer ran>
HEAD=$(git rev-parse HEAD)
PKG=$(sprint-plan review-package "$BASE" "$HEAD")   # writes review-<BASE>-<HEAD>.md

# Dispatch reviewer with: brief path + report path + review-package path + global constraints
```

### Red flags — stop if you catch yourself

| Thought | Reality |
|---------|---------|
| "It's faster to paste the task into the prompt" | Pastes stay in your context forever; file paths don't |
| "Subagent needs the whole plan for context" | It needs its task + the interfaces it consumes. Nothing else. |
| "Let me paste the spec section too" | Put spec excerpts into the brief via Plan phase, not ad-hoc in dispatch |
| "Subagent should read .sprint/CURRENT" | Anchor file is for the coordinator's `sprint-plan` commands, not subagents |
| "I'll let the implementer read PLAN.md this once" | One read becomes a pattern. Slice it. |
| "Skip the review package, just give the diff inline" | Inline diffs bloat your context; reviewers prefer one file |

### Anti-patterns

- **Don't spawn subagents that read the same files** — coordinate targets
- **Don't let subagents write to the same files** — partition by module
- **Don't pass full file contents to subagents** — give them file paths and let them read
- **Don't summarize subagent output twice** — once in main context is enough
- **Don't paste prior-task summaries into later dispatches** — a real session hit 42k chars, 99% pasted history. The brief is the brief.
- **Don't dispatch a task without a diff file for the reviewer** — generate `sprint-plan review-package BASE HEAD` first
- **Don't re-dispatch tasks the ledger already marks complete** — check `.sprint/<task>/STATE.yaml` recent_actions + `git log` after any compaction

## Handling Implementer Status

| Status | Coordinator action |
|--------|-------------------|
| `DONE` | Generate review package, dispatch reviewer |
| `DONE_WITH_CONCERNS` | Read concerns; correctness/scope concerns → fix before review; observations → proceed |
| `NEEDS_CONTEXT` | Provide the missing context, re-dispatch (same model) |
| `BLOCKED` | (1) more context → same model; (2) more reasoning → bigger model; (3) too large → split; (4) plan wrong → escalate to user |

Never force the same model to retry without changes. If it said BLOCKED, something must change.

## Parallel Execution Patterns

### Research Phase
Spawn 2-3 subagents in parallel, each exploring a different code path or module:
```
Subagent 1: "Trace authentication flow from entry to DB. Return file paths and key functions, under 200 words."
Subagent 2: "Map data model and schema relationships. Return table names and foreign keys, under 200 words."
Subagent 3: "Find all error handling patterns. Return file paths and patterns found, under 200 words."
```

### Implement Phase
One task per subagent, each consuming its own brief file:
```
Subagent A (Task 1): brief=<temp>/task-1-brief.md, report=<temp>/task-1-report.md
Subagent B (Task 2): brief=<temp>/task-2-brief.md, report=<temp>/task-2-report.md
```
Sequential by default (tasks share state via `task-N-brief.md` Consumes/Produces). Parallel only when tasks are file-disjoint AND interface-independent.

### Review Phase
Spawn bug hunter + security auditor with different lenses (see `/keep:review` skill).

## Fork Recursion Guard

Subagents spawning subagents must have a depth limit (max 2 levels). Without guard: exponential context cost, timeout cascades, stale references. Pattern: pass `--max-depth N` or check parent context before delegating.
