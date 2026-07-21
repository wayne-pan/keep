## Core Workflow

Closed-loop: Perceive → Build → Verify → Self-Heal.
Loop Engineering (one floor above this harness, unattended): see rules/loop-engineering.md and `/keep:loop`.

### Direct Answer
- Read-only queries (list, describe, summarize, explain): answer from prompt directly.
- Do NOT use tools unless answer is genuinely unavailable from context.
- Never expand scope beyond what was asked.

### Task Classification
| Scope | Criteria | Gate |
|-------|----------|------|
| Trivial | 1 file, <5 lines, no design | BUILD→VERIFY |
| Standard | 1-2 files, <50 lines | READ→BUILD→VERIFY |
| Complex | 3+ files OR design OR >50 lines | trigger `/keep:sprint` (features/refactors) OR `/keep:diagnosing-bugs` (bugs/regressions); both replace built-in plan mode |

Target: trivial ≤2 turns, standard ≤3, complex: routed to `/keep:sprint` or `/keep:diagnosing-bugs` (typically 15-30 turns; phase count per skill).

### Think Before Coding
- State assumptions explicitly. If uncertain, ask — don't guess silently.
- Multiple interpretations exist? Present them, don't pick one and run.
- If a simpler approach exists, say so. Push back when warranted.
- Confused? Stop. Name what's unclear. Ask.

### Build Discipline
- Complex work (3+ files OR design OR >50 lines) → `/keep:sprint` for features/refactors, `/keep:diagnosing-bugs` for bugs/regressions. Standard-scope (1-2 files) needs no separate plan phase — its READ step already covers lightweight planning.
- Tests pass → stop. Don't refactor passing code
- Search codebase for existing utils before writing new ones
- Every changed line must trace to user request
- Simplicity gate (your own code): if your first draft is 200 lines and a 50-line equivalent exists with same behavior, use the shorter version. No unused features, abstractions, or error handling for failure modes the current call site cannot produce.
- Surgical edits: don't "improve" adjacent code, comments, or formatting. Match existing style (except where existing style violates the simplicity gate). Notice unrelated dead code — mention it, don't delete it.
- Re-classification: if a Standard task grows past 2 files or 50 lines mid-execution, snapshot current state (commit or stash partial work), then re-route to `/keep:sprint` Phase 2 (feature/refactor) or `/keep:diagnosing-bugs` Phase 1 (bug/regression). Do not keep going in Standard mode.

### Verify & Self-Heal
- After editing: check syntax, run tests, scan stderr
- Error protocol: read error → search memory → fix root cause → ONE retry → rollback → escalate
- 3 same-type fails → STOP, escalate to user
- Goal-driven verification (standard+complex, when test framework available): transform tasks into testable goals. "Add X" → "Write test for X, then make it pass". "Fix bug" → "Write reproducing test, then make it pass". For multi-step: state plan as `Step → verify: check`. Loop until goal met.

### Guardrails
- >30 tool calls: compress context, narrow focus
- >10 files touched: split task or delegate to Agent
- >80 tool calls: STOP, summarize, suggest fresh session

### Subagent Returns
All subagents must return: `{"summary", "confidence": 0-1, "findings": [], "status": "done|need_more|error"}`. Summary ≤200 words.

### Memory Protocol
Tiers: immutable (never pruned), append-only (summarized), overwritable (pruned freely). Tag with `concept:<tier>`.
Relations: `rel:<type>:<id>` in concepts field. Types: supersedes, contradicts, derived_from, relates_to, in_cluster.
Conflict: higher-confidence wins; delta<0.2 → flag for human review.
Retrieval: `search → get_observations → related(depth=2) → verify`. Decay: immutable=none, append-only=5%/yr, overwritable=20%/yr.
Project scoping: always pass `project` to remember/recall/search/wakeup. Current project = `$(basename $PROJECT_DIR)`. Project-scoped queries get project filter; cross-project queries (preferences, general patterns) omit it.

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
On session start, run four steps in order:

1. `wakeup(project)` — load synthesis + recent observations into context.
2. `search("session-checkpoint", project=project)` — pull the most recent checkpoint. Checkpoints are append-only.
3. Handoff check: `ls -t "${TMPDIR:-/tmp}"/keep-handoff-*.md 2>/dev/null | head -1`. If a handoff file exists, read it before presenting — it carries in-flight work, suggested next skills, and decisions not to re-litigate. The handoff is a fork (one-shot), not state — delete or archive it after consuming.
4. Present to user: current branch, dirty files, modified files since last session, and (if handoff was found) the top 1-3 next moves with their suggested skills.

Three sources, three roles — don't conflate them:
- `wakeup` reloads memory **state** (synthesis, decisions, observations).
- `session-checkpoint` captures the **previous session's tail** (decisions, modified files, identifiers).
- `keep-handoff-*.md` carries **conscious handoff intent** (next moves, suggested skills, open questions) — present only when the previous session explicitly handed off, not every resume.

### Bash
- Every cmd: check exit code, scan stderr
- Critical ops: verify effect (file exists, service up)

### Destructive Ops Checklist
1. Data loss: what lost? recoverable?
2. Side effects: downstream hit?
3. Safer alt: --soft, --no-ff, backup, dry-run
4. Recovery: can undo? how?
5. Git: suggest --soft/revert first, reflog as recovery
