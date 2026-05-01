# Disk-Driven State Machine

All sprint state lives on disk in `.sprint/`. Context compaction is safe — state survives in files, not memory. This is inspired by GSD-2's disk-driven architecture where the filesystem is the source of truth.

## State Files

| File | Purpose | Updated by |
|------|---------|-----------|
| `STATE.yaml` | Current phase, progress, file lists | Every phase transition |
| `RESEARCH.md` | Compressed research findings | Research phase |
| `DECISIONS.md` | Architecture decisions + rationale | Plan phase, ad-hoc |
| `KNOWLEDGE.md` | Project-specific knowledge (append-only) | Any phase |
| `STUCK.md` | Stuck detection diagnosis | When stuck detected |

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
- KNOWLEDGE.md may be preserved in project root if valuable
