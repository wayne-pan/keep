# Disk-Driven State Machine

All sprint state lives on disk under `.sprint/` — one root, two scopes. Context compaction is safe — state survives in files, not memory. This is inspired by GSD-2's disk-driven architecture where the filesystem is the source of truth.

**One task = one directory.** Each sprint gets `.sprint/<task>/` (created at sprint start), so different tasks never overwrite each other's PLAN.md, STATE.yaml, briefs, or reports. The active task is named by the `.sprint/CURRENT` anchor, which sibling commands (`sprint-plan *`, `sprint-checkpoint *`) read back after `cd` shifts or context compaction.

## One Root, Two Scopes

| Scope | Holds | Lifecycle |
|-------|-------|-----------|
| `.sprint/<task>/` | STATE.yaml, RESEARCH.md, DECISIONS.md, CHECKPOINT.yaml, STUCK.md, PLAN.md, briefs, reports, review packages | Created at sprint start via `sprint-plan init <name>`, deleted at Ship via `sprint-plan clear` |
| `.sprint/` root | CURRENT anchor, KNOWLEDGE.md, FINDINGS.md, CODE_MAP.md, EXPERIMENTS.tsv, TRIPLETS.jsonl | Persists across sprints |

## Per-Task Directories + Anchor Protocol

`sprint-plan.sh` resolves the repo root via `git rev-parse` (so commands work from any subdirectory) and manages:

- `sprint-plan init [name]` — sanitizes the name (allowlist `[A-Za-z0-9._-]`, reserved names like `CURRENT`/`KNOWLEDGE.md` rejected), creates `.sprint/<name>/`, and writes the name to `.sprint/CURRENT`. No name → timestamped `sprint-<YYYYmmdd-HHMMSS>` (always a fresh dir). Re-running `init` with an existing name **resumes** that task — state intact.
- Every consuming command reads `.sprint/CURRENT`, re-validates the name (blocking path traversal and reserved-name collisions), and resolves the absolute task dir. Missing anchor → clear error: `sprint-plan init <name>` first.
- `sprint-plan list` shows all task dirs with the active one marked; `sprint-plan clear` removes only the active task dir + anchor.

## State Files (task dir unless noted)

| File | Purpose | Updated by |
|------|---------|-----------|
| `STATE.yaml` | Current phase, progress, file lists | Every phase transition |
| `RESEARCH.md` | Compressed research findings | Research phase |
| `DECISIONS.md` | Architecture decisions + rationale | Plan phase, ad-hoc |
| `KNOWLEDGE.md` *(root)* | Project-specific knowledge (append-only, cross-sprint) | Any phase |
| `FINDINGS.md` *(root)* | Cross-session insights (append-only, cross-sprint) | Reflect phase |
| `EXPERIMENTS.tsv` *(root)* | Benchmark experiment log (iteration, metric, delta, status) | Benchmark runs |
| `TRIPLETS.jsonl` *(root)* | Structured test triplets (state, action, reward) for regression tracking | Test phase |
| `CHECKPOINT.yaml` | Phase boundary checkpoint (see schema below) | Each phase boundary |
| `STUCK.md` | Stuck detection diagnosis | When stuck detected |
| `CURRENT` *(root)* | Anchor: name of the active task | `sprint-plan init` / `sprint-plan clear` |

## Plan Artifacts (task dir)

| File | Purpose | Written by |
|------|---------|-----------|
| `PLAN.md` | Structured implementation plan (Phase 2 output) | `sprint-plan write-plan` (Plan phase) |
| `task-N-brief.md` | Per-task slice consumed by implementer subagents | `sprint-plan task-brief <N>` (before each dispatch) |
| `task-N-report.md` | Per-task implementer report (status, commits, test summary, concerns) | Implementer subagent |
| `review-<BASE>-<HEAD>.md` | Diff package (commits + stat + unified diff) for reviewer subagents | `sprint-plan review-package <BASE> <HEAD>` |

## STATE.yaml Schema

```yaml
phase: research       # research|plan|implement|review|test|ship|done
iteration: 1          # increments on stuck detection reset
files_examined: []    # files read during research
files_modified: []    # files changed during implement
decisions: []         # [{what: "use X", why: "Y", phase: "plan"}]
gaps_found: []        # knowledge gaps from research loop
recent_actions: []    # last 5 actions for stuck detection
started: "2026-04-08T00:00:00Z"
last_update: "2026-04-08T00:05:00Z"
```

## RESEARCH.md Format

```markdown
# Research Findings

## Code Structure
- `path/to/file:15-30` — core handler function, takes X, returns Y
- `path/to/other:42` — helper that validates Z

## Data Flow
Input → handler() → validator() → output

## Dependencies
- module A depends on B (line 15 import)
- config loaded from settings.json

## Constraints
- Must maintain backward compat with X
- Performance requirement: < 100ms

## Gaps
- [ ] How does X handle edge case Y?
- [ ] What's the migration path for Z?
```

## DECISIONS.md Format

```markdown
# Architecture Decisions

## [2026-04-08] Use wrapper pattern for dry-run
- **Context**: Need to add --dry-run without modifying core logic
- **Decision**: Extract `run_cmd()` wrapper instead of if/else everywhere
- **Alternatives considered**: (1) flag per command (2) env var override
- **Why**: Wrapper keeps core logic clean, testable in isolation

## [2026-04-08] Use regex validation for input
- **Context**: Need to sanitize user input
- **Decision**: Use allowlist regex pattern, not blocklist
- **Why**: Blocklists always miss edge cases. Allowlist is finite and auditable.
```

## KNOWLEDGE.md Format

Append-only — never delete, only add. This accumulates project knowledge across sprints.

```markdown
# Project Knowledge

## [2026-04-08] Config file location
- Main config: `~/.config/app/config.json`
- Local override: `.app/config.local.json`
- Local takes precedence

## [2026-04-08] Test infrastructure
- Framework: pytest
- Run: `pytest tests/ -v`
- Coverage: `pytest --cov=src tests/`
```

## Lifecycle

### Phase Start
1. Read `STATE.yaml` to determine current phase
2. Read the relevant phase file (RESEARCH.md for Research, etc.)
3. Restore context from compressed state

### Phase Work
1. Execute phase tasks
2. Append findings/decisions to relevant files
3. Update `STATE.yaml` with progress (files examined, decisions made)

### Phase End
1. Write compressed summary to the phase file
2. Update `STATE.yaml`: phase, last_update, recent_actions
3. If transitioning to Implement: write DECISIONS.md with plan decisions

### Session Resume (after context compaction or crash)
1. Read `STATE.yaml` — what phase, what's done
2. Read last updated phase file — what was happening
3. Continue from where left off

### Cleanup
- `sprint-plan clear` at Ship phase completion (after Reflect) — removes the active task dir (STATE, PLAN, briefs, reports, review packages, CHECKPOINT) and the `.sprint/CURRENT` anchor
- `.sprint/` root persists: KNOWLEDGE.md and FINDINGS.md accumulate across sprints
- Other task dirs (abandoned or past sprints) are untouched — inspect via `sprint-plan list`

## CHECKPOINT.yaml Schema

Saved at each phase boundary by `sprint-checkpoint save <phase> <step>` into the active task dir. On sprint start, `sprint-checkpoint resume` returns the active task's checkpoint (or `none`).

```yaml
phase: implement
step: "module-3"
files_modified: "file1.sh,file2.py"
timestamp: "2026-04-29T10:00:00Z"
remaining: [review, test, ship]
pending_decisions: []
```

## KV Store Lifecycle

The KV store provides shared state between sub-agents:

- **Setup**: auto-initializes on first `kv-set` call (per session)
- **Usage**: sub-agents write findings via `kv-set`, coordinator reads via `kv-get`
- **Teardown**: `kv-clear` at sprint completion (temp dir auto-cleaned on reboot)
