# Loop Engineering

Replacing yourself as the person who prompts the agent — you design the system that does it instead. Sits **one floor above the harness**. Orchestrate, don't reimplement.

Use these terms exactly. Don't substitute "automation," "pipeline," or "bot."

## The Stack

Four floors. Each floor wraps the one below.

| Floor | Layer | What lives here |
|-------|-------|-----------------|
| 4 | **Loop** | Unattended revolution of moves; evaluator gate; budget. This layer. |
| 3 | Harness | Skills, hooks, crons, MCP, worktrees, sub-agents — keep's own primitives. |
| 2 | Context | File contents, memory, diffs — what the model sees. |
| 1 | Prompt | The token sequence sent to the model. |

A loop floor composes harness primitives into a self-running circuit. It adds **no** new primitive. If you are writing a new cron / worktree / memory / sub-agent shim, you are on the wrong floor.

## Terms

**Loop** — One unattended revolution through the five moves. Has a name, a spec, and a state file. _Avoid_: automation, pipeline, bot.

**Move** — One of the five stages of a revolution. A move has a done-criteria, not just an action.

**Spec** — Declarative loop definition at `.loop/<name>/loop.yaml`. Edits to the spec are how you steer the loop — not edits to the harness.

**Generator** — Agent that drafts a change. Cannot grade itself.

**Evaluator** — Fresh agent, different instructions, ideally different model, that says pass/fail on the generator's output. The evaluator is the loop's load-bearing part — weak evaluator, weak loop.

**Revolution** — One completed pass Discovery → Scheduling. Multiple revolutions per scheduled fire is the norm.

**Budget** — Hard ceiling on tokens and iterations per revolution and per day. The countermeasure to token runaway (§07).

**State file** — `.loop/<name>/STATE.md`. Cross-revolution memory. "Agent forgets, repo doesn't."

## The Five Moves

One revolution = these five, in order. Each move has a done-criteria, not just an action.

| # | Move | Does | Done when | Primitive |
|---|------|------|-----------|-----------|
| 1 | **Discovery** | Find what's worth doing | Findings written to `.loop/<name>/inbox.md` (may be empty → `no_findings`) | `discovery.ref` skill via `Agent` |
| 2 | **Handoff** | Draft the change in isolation | Worktree has a candidate change | `EnterWorktree` + generator `Agent` |
| 3 | **Verification** | Adversarial check of the draft | Stop-check returns `STOP` (ESCALATE halts rev) | evaluator `Agent` + fresh fast model for stop-check |
| 4 | **Persistence** | Write what happened | STATE.md updated; merge per strategy | inline write + `mcp__mind__*` |
| 5 | **Scheduling** | Decide the next fire | Next cron registered or noted | `CronCreate` |

Operational table with per-Move protocols and an Output column: `skills/loop/SKILL.md` (run sub-mode). The table above is conceptual; the SKILL.md table is the executable counterpart. Edit them together.

A move that cannot satisfy its done-criteria halts the revolution and writes the halt reason to STATE.md. Do not silently skip a move.

## Six Parts → keep Primitives

The document (§04) names six parts a loop is built from. All six already exist as keep primitives. Loop wires them; it does not build them.

| Part | Document role | keep primitive |
|------|---------------|----------------|
| **Automations** | Trigger a revolution | `CronCreate` / `CronList` / `CronDelete` |
| **Worktrees** | Isolate the generator's draft | `EnterWorktree` / `ExitWorktree` |
| **Skills** | Discovery source — fire a skill, don't write a wall of instructions | `skills/*/SKILL.md` |
| **Connectors** | Reach outside the repo | MCP servers (mind, codedb, web_reader, 4_5v_mcp) |
| **Sub-agents** | Generator + evaluator | `Agent` with `model` + `subagent_type` |
| **Memory** | Cross-revolution continuity | `mcp__mind__*` + `.loop/<name>/STATE.md` |

Deletion test: delete the loop layer. The six parts still work; you just lost the orchestrator. Complexity did not vanish — it reappeared as you, manually prompting. The layer earned its keep.

## Generator / Evaluator

Maker-checker. The maker cannot be the checker.

- **Different agent.** Mandatory. The evaluator has no shared context with the generator — fresh prompt, fresh turn.
- **Different model.** Recommended. If the generator is `sonnet`, the evaluator is `opus` (or vice versa). A model that graded itself will rubber-stamp itself.
- **Hands-on.** For `hands-on` tier: run tests, run the build, drive a browser. Read-the-diff-only is not verification.
- **Skepticism-calibrated.** Default prior: "this is broken until proven otherwise." The evaluator's job is to fail the draft, not to praise it.

The stop-condition is **not** the evaluator's verdict alone. A fresh model re-reads the verdict and the diff each turn, **re-runs the primary check independently**, and decides stop/continue. This third agent has no shared state with the generator or the evaluator — it exists to break collusion. This blocks the evaluator rubber-stamping the generator across turns.

**Model-class isolation is load-bearing.** The stop-check MUST use a different model class than the evaluator (haiku vs sonnet vs opus). Same-class pairs defer to each other under pressure even with explicit anti-deferral instructions.

**ESCALATE handling.** When the stop-check returns ESCALATE: halt the revolution (no further findings), still write Move 4 persistence (audit trail), skip Move 5 scheduling (no auto-reschedule — human must re-arm).

Full construction detail: `skills/loop/references/evaluator.md`.

## Four Costs (§07) and Countermeasures

A loop left to its own devices incurs four costs. Each has a countermeasure that lives in the spec.

| Cost | What happens | Countermeasure |
|------|--------------|----------------|
| **Verification debt** | Evaluator gets weaker over revolutions as drift accumulates | Rotate evaluator prompt; log verdicts in STATE.md for human audit |
| **Understanding rot** | Humans forget what the loop is doing | STATE.md is the contract; human checkpoint on listed moves |
| **Cognitive surrender** | You stop checking the loop's work | `human_checkpoint` in spec; budget cap forces re-entry |
| **Token runaway** | Loop spends without producing | `budget.max_iterations_per_rev` + `daily_cap_tokens`; halt at cap |

If any cost is left uncountered, the loop is not engineered — it is abandoned.

## The Six-Item Checklist (§09)

Refuse to `define` a loop complete until all six are answered. This is the gate.

1. **Discovery source** — skill | script | mcp. Named concretely, not "look around."
2. **State file** — `.loop/<name>/STATE.md`. Always. No state = no loop.
3. **Evaluator** — model + tier (`quick-gate` | `deep` | `hands-on`) + skepticism.
4. **Isolation** — worktree per finding. The generator never edits the main tree directly.
5. **Caps** — `max_iterations_per_rev` (hard halt, generator-spawn count) + `daily_cap_tokens` (advisory only until the harness exposes per-call usage; see SKILL.md Budget Enforcement caveat).
6. **Human checkpoint** — which moves pause for human. Empty is a valid answer only if you accept cognitive surrender.

## Principles

- **One floor up.** If you are writing a new primitive, you are on the wrong floor.
- **Spec, not code.** Steer by editing `.loop/<name>/loop.yaml`, not by patching the harness.
- **Agent forgets, repo doesn't.** STATE.md is the only cross-revolution memory the loop can rely on. Memory MCP is for synthesis, not for in-flight state.
- **The evaluator is the load-bearing part.** A loop with a weak evaluator has no foundation.
- **Local cron needs the machine on.** For loops that must run while you sleep, point at GitHub Actions / Cloud Routines — not `CronCreate`. Document this honestly in the spec.
- **3-day cron expiry.** `CronCreate` recurring jobs auto-expire after 3 days. Re-schedule at session start, or note in STATE.md that the loop is dormant.

**See also**: `rules/graph-engineering.md` — the layer above this one. A loop is the inside of a graph node.
