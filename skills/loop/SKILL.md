---
name: keep:loop
version: "1.1"
triggers: ["/keep:loop", "/keep:set up a loop", "/keep:run unattended", "/keep:automate this task", "/keep:loop engineering"]
routes_to: ["review", "sprint"]
description: >
  Loop Engineering — design and run unattended five-move loops that sit one floor
  above the harness. TRIGGER when: user says /keep:loop, "set up a loop", "run
  unattended", "automate this task", or references loop engineering. Four sub-modes:
  define (interview + write loop.yaml), run (one revolution of the five moves),
  schedule (register with cron), list (show loops). Orchestrates existing primitives
  (Agent, EnterWorktree, CronCreate, mcp__mind__*) — does not reimplement them.
  Do NOT trigger for: one-off sprints (use /keep:sprint), background memory
  maintenance (use /keep:ambient), or single reviews (use /keep:review).
resources: ['subagents', 'worktrees', 'cron', 'mind']
---

# Loop Engineering

One floor above the harness. Compose existing primitives into the five moves — Discovery, Handoff, Verification, Persistence, Scheduling — with the evaluator as the load-bearing part and budget as the hard ceiling.

**If you are writing a new worktree/cron/memory/sub-agent shim, stop.** All six parts (Automations, Worktrees, Skills, Connectors, Sub-agents, Memory) already exist as keep primitives; this skill wires them.

**Syntax note.** `Agent(model=..., subagent_type=...)` and `EnterWorktree(...)` are Claude Code tool invocations. On other harnesses (Codex, OpenCode) the same primitives exist under different syntax — adapt the call site, the orchestration shape is portable.

Vocabulary + principles: `rules/loop-engineering.md`. Evaluator construction: `references/evaluator.md`. Move execution detail: `references/moves.md`. Spec schema + interview: `references/spec-schema.md`.

## Sub-Mode Selection

Pick by leading keyword. If ambiguous, ask.

| Trigger | Sub-mode |
|---------|----------|
| `/keep:loop define <name>` | define — interview, write spec |
| `/keep:loop run <name>` | run — execute one revolution |
| `/keep:loop schedule <name>` | schedule — register cron |
| `/keep:loop list` | list — show loops in `.loop/` |
| `/keep:loop` (bare) | list, then offer to define |

## `define <name>` — Interview + Spec

Walk the user through the §09 six-item checklist. Refuse to complete until all six answered. Full interview, schema template, and `discovery.ref` validation: `references/spec-schema.md`.

Output: `.loop/<name>/loop.yaml` + `.loop/<name>/STATE.md` (header only, status=dormant). Do **not** start the loop in `define` — use `schedule` or `run` after.

## `run <name>` — One Revolution

Resource check first (see `references/spec-schema.md`). Halt with reason `missing_primitive` if any primitive absent — do not fall back silently.

Execute the five moves in order, reading the spec. Each move has a done-criterion, not just an action. Full per-move execution detail: `references/moves.md`.

### The Five Moves (overview)

| # | Move | Primitive | Done when |
|---|------|-----------|-----------|
| 1 | Discovery | `Agent` running `discovery.ref` skill | `inbox.md` written (may be empty → `no_findings`) |
| 2 | Handoff | `EnterWorktree` per finding + generator `Agent` | worktree has a candidate change |
| 3 | Verification | evaluator `Agent` + stop-check `Agent` (different model class) | stop-check returns `STOP` |
| 4 | Persistence | inline write STATE.md + `mcp__mind__remember` | STATE.md has this revolution logged |
| 5 | Scheduling | `CronCreate` if `schedule` non-empty and not registered | next fire recorded, or "manual run only" |

A move that cannot satisfy its done-criteria halts the revolution and writes the halt reason to STATE.md.

**Move 2 seeding.** `EnterWorktree` branches from HEAD — dirty/untracked files in the main tree do not follow the generator in. If the finding depends on in-flight files, seed them right after `EnterWorktree`:

<!-- seed-begin -->
```bash
# Seed dirty/untracked files from the main repo into a fresh worktree.
: "${SEED_SRC:?export SEED_SRC=<main-repo-dir>}" "${SEED_DST:?export SEED_DST=<worktree-dir>}"
git -C "$SEED_SRC" status --porcelain | cut -c4- | grep -Ev '\.(log|tmp)$' | while IFS= read -r f; do
  mkdir -p "$SEED_DST/$(dirname "$f")"
  cp "$SEED_SRC/$f" "$SEED_DST/$f" 2>/dev/null || true
done
```
<!-- seed-end -->

### Generator/Evaluator Model Rules

- Generator model ≠ evaluator model (recommended).
- Stop-check model class ≠ evaluator model class ≠ generator model class (mandatory).
- ESCALATE halts the revolution: Move 4 still runs (audit), Move 5 skipped (no auto-reschedule).

## `schedule <name>` — Register Cron

Read `spec.schedule`. Check `CronList` for existing entry. If absent, `CronCreate` per Move 5. If present, report existing job id and next fire.

Be honest: this schedules a fire **only when the local Claude Code session is open**. It does not wake a sleeping machine. For 24/7 loops, the spec must point at an external runner (GitHub Actions, Cloud Routines). State this explicitly to the user when scheduling.

## `list` — Show Loops

Scan `.loop/*/loop.yaml`. For each:

- name
- schedule (or "manual")
- last revolution (from STATE.md): date, verdict, halt_reason if any
- next cron fire (from `CronList`) or "dormant"
- today's token spend vs cap (from STATE.md)

Format:

```
triage-ci    schedule=0 9 * * *   last=2026-06-17 pass   cron=active   today=12k/200k
refactor-bot schedule=manual      last=2026-06-15 halt   cron=dormant  today=0/200k
```

## Budget Enforcement

**Token accounting caveat (data-source gap).** Sub-agent JSON returns (5-key contract: `summary, confidence, findings, deeper_question, status`) do **not** include usage metadata. Until the harness exposes per-call usage, `daily_cap_tokens` is **advisory only** — operator must read the harness's session-end usage report and record it manually in STATE.md.

The `max_iterations_per_rev` cap IS enforceable: it counts generator spawns, which the orchestrator controls directly. Before each move, count iterations. **Within Move 2, the count is checked before EACH generator spawn, not just at move entry** — otherwise a multi-finding inbox would spawn N generators before any check fires. Halt reasons: `rev_cap_reached` (iterations ≥ cap), `daily_cap_reached` (when usage data is available and ≥ cap).

Halt is not failure. Halt is the budget doing its job (§07 countermeasure for token runaway + cognitive surrender). Write the halt to STATE.md and surface to user.

## Human Checkpoint

For each move listed in `human_checkpoint`:

1. Complete the move's action.
2. Stop. Write "awaiting human review — resume with `/keep:loop run <name>`" to STATE.md.
3. Do not proceed to the next move until the user re-invokes `run`.

Default recommendation: `[persistence]`. Empty list is allowed only if the user explicitly accepts the cognitive-surrender cost.

## Safety

- Generator never edits the main tree directly — worktree is mandatory (Move 2).
- `safety-guard.sh` covers **Bash** destructive commands (Tier-2); `protect-files.sh` covers Edit/Write on protected paths only. A `direct` merge via Edit/Write is **not** fully covered by safety-guard.sh — review the diff manually before applying, or prefer the `pr` strategy.
- A loop that fails verification three revolutions in a row should be paused and reviewed, not restarted. Surface to user.

## References

- `references/spec-schema.md` — loop.yaml schema, define interview, resource check, cron caveat
- `references/moves.md` — Move 1–5 execution detail, halt conditions, ESCALATE handling
- `references/evaluator.md` — evaluator construction, three tiers, maker-checker, verbatim prompt template
- `rules/loop-engineering.md` — vocabulary and principles for the loop layer
