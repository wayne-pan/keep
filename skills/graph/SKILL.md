---
name: keep:graph
version: "1.0"
triggers: ["/keep:graph", "/keep:graph define", "/keep:graph run", "/keep:graph list", "multi-agent graph", "wire agents", "graph engineering"]
routes_to: ["loop", "review", "sprint"]
description: >
  Graph Engineering — design and run multi-node agent graphs that sit one floor
  above loop engineering. TRIGGER when: user says /keep:graph, "multi-agent graph",
  "wire agents", "graph engineering", or needs to coordinate multiple specialized
  agents with edges and shared state. Three sub-modes: define (interview + write
  graph.yaml), run (one traversal), list (show graphs). Orchestrates existing
  primitives (Agent, EnterWorktree, kv-*, mcp__mind__*) — does not reimplement them.
  Do NOT trigger for: one-off sprints (use /keep:sprint), recurring single-agent
  tasks (use /keep:loop), or single reviews (use /keep:review).
resources: ['subagents', 'worktrees', 'kv', 'mind']
---

# Graph Engineering

One floor above loop engineering. Wire multiple specialized agents into a coordinated system — nodes that do the work, edges that route between them, shared state flowing along the edges.

## ⚠ Try Loop First

**Most tasks don't need a graph.** A single well-scoped agent with a good verifier is a loop, and reaching for a graph there is pure overhead.

Before `/keep:graph`, ask honestly:
- Does the task split into distinct specialties that hand off? → maybe graph
- Do you need fan-out (many agents at once)? → maybe graph
- Does each step need a different model or toolset? → maybe graph
- Is there a dedicated reviewer node that checks another node's work? → maybe graph

If most answers are "no," use `/keep:loop`. You engineered an org chart to answer an email if you build a 5-node graph for something one loop could handle.

**Deletion test**: delete the graph layer. If complexity vanishes, it was a pass-through. If it reappears as you manually wiring sub-agents with pasted context, it earned its keep.

Vocabulary + principles: `rules/graph-engineering.md`.

## Sub-Mode Selection

Pick by leading keyword. If ambiguous, ask.

| Trigger | Sub-mode |
|---------|----------|
| `/keep:graph define <name>` | define — interview, write spec |
| `/keep:graph run <name>` | run — execute one traversal |
| `/keep:graph list` | list — show graphs in `.graph/` |
| `/keep:graph` (bare) | list, then offer to define |

## `define <name>` — Interview + Spec

Walk the user through the 6-question interview (see `references/spec-schema.md` → Define Interview). Refuse to complete until all six answered.

Output: `.graph/<name>/graph.yaml` + `.graph/<name>/STATE.md` (header only, status=dormant). Do **not** start the graph in `define` — use `run` after.

Validate before writing (see `references/spec-schema.md` → Validate Before Writing Spec):
- Node names unique
- Edges reference real nodes
- At least one exit path
- Skill refs exist (Glob `skills/*/SKILL.md`)
- No cycles without `budget.max_iterations`

## `run <name>` — One Traversal

Resource check first (see `references/spec-schema.md` → Resource Check). Halt with reason `missing_primitive` if any primitive absent — do not fall back silently.

Execute per `references/nodes.md`:

1. Read `graph.yaml`.
2. Initialize state: write `state.initial` to `.graph/<name>/state.yaml`.
3. Determine entry node.
4. Traverse: for each node, read input → spawn agent per type → await → write output → evaluate edges.
5. Budget check before each node spawn.
6. On exit or halt: append revolution record to `.graph/<name>/STATE.md`.

### Edge Execution

- **No edges section**: nodes run in declaration order.
- **With edges section**: fully edge-driven (straight / fan-out / fan-in / conditional — see `references/nodes.md`).
- Fan-out: issue N `Agent` calls in a single response; harness executes in parallel.
- Fan-in: all upstream nodes must return before the downstream proceeds.
- Conditional (`when: pass|fail|always`): edge fires only if upstream verdict matches.

### Node Types

| Type | Invokes | Output capture |
|------|---------|----------------|
| `agent` | `Agent(model, skill, prompt)` | Return JSON → state |
| `loop` | `/keep:loop run <name>` | Read `.loop/<name>/STATE.md` last entry |
| `sprint` | `EnterWorktree` + `/keep:sprint build` | Read worktree `git diff HEAD` |

## `list` — Show Graphs

Scan `.graph/*/graph.yaml`. For each:

- name + description
- node count + edge count
- last revolution (from STATE.md): date, verdict, halt_reason if any
- status: dormant / active / halted

Format:

```
pr-review     nodes=5 edges=4   last=2026-07-22 pass    status=dormant
research-bot  nodes=3 edges=2   last=2026-07-20 halt    status=halted (budget_exceeded)
```

## Budget Enforcement

**Token accounting caveat.** Same as loop: sub-agent JSON returns do not include usage metadata. `budget.max_tokens` is **advisory only** until the harness exposes per-call usage. Operator must read the harness's session-end usage report and record it manually in STATE.md.

`budget.max_iterations` IS enforceable: it counts total node spawns, which the coordinator controls directly. Before each node spawn, check iteration count. Halt reasons: `iterations_exceeded` (spawns >= cap).

Halt is not failure. Halt is the budget doing its job. Write the halt to STATE.md and surface to user.

## Human Checkpoint

For each node listed in `human_checkpoint`:

1. Complete the node's action.
2. Stop. Write "awaiting human review — resume with `/keep:graph run <name>`" to STATE.md.
3. Do not proceed to downstream nodes until the user re-invokes `run`.

Default recommendation: `[synthesis]` or `[ship]` — the nodes that commit to an irreversible outcome. Empty list is allowed only if the user explicitly accepts the cognitive-surrender cost.

## Safety

- **Worktree per side-effecting node**: `type=sprint` and `type=loop` nodes get their own worktree (via `EnterWorktree`).
- **safety-guard.sh** covers Bash destructive commands (Tier-2). `type=agent` nodes editing the main tree must respect `protect-files.sh`.
- **Never edit main tree** for speculative changes — all side effects go through worktrees.
- **Two same-type node failures in a row** → halt graph, surface to user.
- **A graph that fails verification three revolutions in a row** should be paused and reviewed, not restarted.

## References

- `rules/graph-engineering.md` — vocabulary and principles for the graph layer
- `references/spec-schema.md` — graph.yaml schema, define interview, validation, worked example
- `references/nodes.md` — node types, edge traversal, state backend, halt semantics
- `references/evaluator.md` — reviewer node pattern, synthesis stop-check (delta on top of loop's evaluator)
- `rules/loop-engineering.md` — the layer directly beneath this one
- `skills/loop/references/evaluator.md` — full evaluator construction (maker-checker, 3 tiers, verbatim prompt)
