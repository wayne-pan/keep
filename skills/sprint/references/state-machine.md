# Disk-Driven State Machine

All sprint state lives on disk in `.sprint/`. Context compaction is safe — state survives in files, not memory. This is inspired by GSD-2's disk-driven architecture where the filesystem is the source of truth.

Plan artifacts (PLAN.md, task briefs, reports, review packages) live in a **session temp dir**, not the project tree. The temp dir path is anchored in `.sprint/PLAN_TMP_PATH` so sibling commands rediscover it after `cd` shifts or context compaction.

## Two Locations, Two Lifecycles

| Location | Holds | Lifecycle |
|----------|-------|-----------|
| `.sprint/` (project) | Phase state, decisions, knowledge, anchor | Created at Research start, deleted at Ship (preserve KNOWLEDGE/FINDINGS) |
| Temp dir (cross-platform) | PLAN.md + per-task briefs/reports + review packages | Created at Plan start via `sprint-plan init`, cleared at Ship via `sprint-plan clear` |

## Cross-Platform Temp Dir Resolution

`sprint-plan.sh` honors this precedence chain:

```
KEEP_SPRINT_TMP  >  TMPDIR  >  TEMP  >  TMP  >  /tmp
```

| Platform | What happens |
|----------|-------------|
| Linux | `$TMPDIR` set (or `/tmp`) — native |
| macOS | `$TMPDIR` set by launchd to `/var/folders/.../T/` — native |
| Windows native bash | `TMPDIR` unset; `$TEMP`/`$TMP` point to `%USERPROFILE%\AppData\Local\Temp` — picked up |
| Git Bash / MSYS2 | Both `/tmp` (mapped) and `$TEMP` work; chain prefers env vars |
| Cygwin | `$TMPDIR` usually set; falls through to `/tmp` |
| WSL | Native Linux semantics |

The chosen path is resolved once at `sprint-plan init` and stored as an absolute path in `.sprint/PLAN_TMP_PATH`. Subsequent commands read the anchor — so later env changes or `cd` shifts don't break the path.

## State Files (`.sprint/`)

| File | Purpose | Updated by |
|------|---------|-----------|
| `STATE.yaml` | Current phase, progress, file lists | Every phase transition |
| `RESEARCH.md` | Compressed research findings | Research phase |
| `DECISIONS.md` | Architecture decisions + rationale | Plan phase, ad-hoc |
| `KNOWLEDGE.md` | Project-specific knowledge (append-only) | Any phase |
| `FINDINGS.md` | Cross-session insights (append-only) | Reflect phase |
| `EXPERIMENTS.tsv` | Benchmark experiment log (iteration, metric, delta, status) | Benchmark runs |
| `TRIPLETS.jsonl` | Structured test triplets (state, action, reward) for regression tracking | Test phase |
| `CHECKPOINT.yaml` | Phase boundary checkpoint (see schema below) | Each phase boundary |
| `STUCK.md` | Stuck detection diagnosis | When stuck detected |
| `PLAN_TMP_PATH` | Anchor: absolute path to the session's temp plan dir | `sprint-plan init` / `sprint-plan clear` |

## Plan Artifacts (temp dir)

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
- Delete `.sprint/` directory at Ship phase completion (after Reflect)
- KNOWLEDGE.md and FINDINGS.md may be preserved in project root if valuable
- Clear temp plan dir: `sprint-plan clear` (removes PLAN.md, all briefs, reports, review packages, and the `.sprint/PLAN_TMP_PATH` anchor)

## CHECKPOINT.yaml Schema

Saved at each phase boundary by `sprint-checkpoint save <phase> <step>`. On sprint start, `sprint-checkpoint resume` returns the most recent checkpoint (or `none`).

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
