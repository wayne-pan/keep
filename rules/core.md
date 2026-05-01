## Core Workflow

Closed-loop: Perceive → Build → Verify → Self-Heal.

### Direct Answer
- Read-only queries (list, describe, summarize, explain): answer from prompt directly.
- Do NOT use tools unless answer is genuinely unavailable from context.
- Never expand scope beyond what was asked.

### Task Classification
| Scope | Criteria | Gate |
|-------|----------|------|
| Trivial | 1 file, <5 lines, no design | BUILD→VERIFY |
| Standard | 1-2 files, <50 lines | READ→BUILD→VERIFY |
| Complex | 3+ files OR design OR >50 lines | IDENTIFY→READ→PLAN→BUILD→VERIFY→CLAIM |

Target: trivial ≤2 turns, standard ≤3, complex ≤8.

### Build Discipline
- Plan mode for non-trivial (3+ steps or architecture)
- Tests pass → stop. Don't refactor passing code
- Search codebase for existing utils before writing new ones
- Every changed line must trace to user request

### Verify & Self-Heal
- After editing: check syntax, run tests, scan stderr
- Error protocol: read error → search memory → fix root cause → ONE retry → rollback → escalate
- 3 same-type fails → STOP, escalate to user

### Guardrails
- >30 tool calls: compress context, narrow focus
- >10 files touched: split task or delegate to Agent
- >80 tool calls: STOP, summarize, suggest fresh session

### Subagent Returns
All subagents must return: `{"summary", "confidence": 0-1, "findings": [], "status": "done|need_more|error"}`. Summary ≤200 words.

### Memory Protocol
Tiers: immutable (never pruned), append-only (summarized), overwritable (pruned freely). Tag with `concept:<tier>`.
Relations: `rel:<type>:<id>` in concepts field. Types: supersedes, contradicts, derived_from, relates_to, in_cluster.
Retrieval: `search → get_observations → related(depth=2) → verify`. Decay: immutable=none, append-only=5%/yr, overwritable=20%/yr.

### Safety Tiers
Tier 1 (auto-allowed): Read, Glob, Grep, git read-only, tests, memory tools, system info.
Tier 2 (requires permission): Edit, Write, git commit/push, install, deploy, network mutations, destructive ops.
Enforcement: safety-guard.sh blocks destructive patterns. This tier is advisory.

### Context Management
- Telegraph style. Preserve code blocks, errors, line refs.
- Files >100 lines: outline/offset, not full read
- Subagent returns: conclusions only (≤200w)
- Memory: store decisions+corrections only, not derivable facts
- Compact at: post-research, post-milestone, pre-shift, 50+ calls
- Before compaction: create session-checkpoint via remember(), preserve checkpoint ID
- Preserve: decisions, task goals, errors, modified files, identifiers. Compress: research, tool output, reasoning.

### Session Resume
On session start: `wakeup(project)` → `search("session-checkpoint")` → present branch/dirty/modified to user. Checkpoints are append-only.

### Bash
- Every cmd: check exit code, scan stderr
- Critical ops: verify effect (file exists, service up)

### Destructive Ops Checklist
1. Data loss: what lost? recoverable?
2. Side effects: downstream hit?
3. Safer alt: --soft, --no-ff, backup, dry-run
4. Recovery: can undo? how?
5. Git: suggest --soft/revert first, reflog as recovery
