# Graph Spec Schema

`.graph/<name>/graph.yaml` — the declarative graph definition. Edits to the spec are how you steer the graph, not edits to the harness.

## Full Schema

```yaml
name: <string>
description: <string>

# Shared state — the object traveling along edges
state:
  initial:
    <key>: <value>

# Nodes — default execution order = declaration order (if no edges section)
nodes:
  - name: <string>                          # unique within this graph
    type: agent | loop | sprint             # what this node runs
    model: haiku | sonnet | opus            # for type=agent (default: sonnet)
    skill: </keep:skill-name>                 # optional: invoke a keep skill (e.g. /keep:review)
    prompt: <string>                         # optional; supports {{state.key}} interpolation
    input: [<state-key>, ...]               # state keys this node reads
    output: [<state-key>, ...]              # state keys this node writes

# Edges — OPTIONAL. Omit entirely for implicit sequential execution.
# Include only when you need fan-out, fan-in, or conditional routing.
edges:
  - from: <node-name> | [<node-name>, ...]
    to: <node-name> | [<node-name>, ...]
    when: pass | fail | always              # conditional on upstream node's verdict

# Budget — hard caps
budget:
  max_tokens: <int>                         # advisory until harness exposes per-call usage
  max_iterations: <int>                     # hard cap on total node spawns (default: 20)

# Optional: human checkpoint at specific nodes
human_checkpoint: [<node-name>, ...]        # pause before these nodes
```

## Node Types

| Type | What it does | When to use |
|------|--------------|-------------|
| `agent` | Direct `Agent(model, skill, prompt)` call | The default. Most nodes are this. |
| `loop` | Invokes `/keep:loop run <name>` and awaits | When a node's job is "iterate until verifier passes" — the loop IS the node. |
| `sprint` | Invokes `/keep:sprint build` in a worktree | When a node's job is "implement this feature" — needs full sprint workflow. |

A node's `type` decides what primitive it invokes. The graph coordinator handles spawning, awaiting, and output capture — see `references/nodes.md`.

## Edge Semantics

### No edges section → implicit sequential

Nodes run in **declaration order**. Each node completes before the next starts. State flows automatically (each node reads its declared `input` keys, writes its `output` keys).

This covers 90% of real graphs: sequential handoffs where each specialty takes the baton.

### With edges section → fully edge-driven

The edges section **replaces** declaration order. Execution follows edges:

- **Straight edge** (`from: A, to: B`): A completes → B starts.
- **Fan-out** (`from: A, to: [B, C, D]`): A completes → B, C, D start in parallel (harness issues N Agent calls in one response; all must return before proceeding).
- **Fan-in** (`from: [B, C, D], to: E`): wait for B, C, D all complete → E starts. State from all upstream nodes is available to E.
- **Conditional** (`from: A, to: B, when: pass`): edge fires only if A's verdict matches. Multiple conditional edges from the same node = branching.
- **Loop-back** (`from: A, to: B, when: fail`): edge back to an earlier node, creating a retry cycle. Enforced by `budget.max_iterations`.

### `when` values

| Value | Edge fires when upstream verdict is |
|-------|-------------------------------------|
| `always` | Any verdict (or no verdict — for deterministic nodes) |
| `pass` | Upstream node returned `verdict: pass` |
| `fail` | Upstream node returned `verdict: fail` |

If a node has no conditional edges leaving it, `when` defaults to `always`.

## State Design Rules

State is the **contract** between nodes. Design it explicitly.

- **Declare reads/writes**: each node's `input` and `output` arrays name the state keys it touches. Undeclared mutations are the #1 cause of state drift.
- **No per-field permissions**: trust the declarations. If a node writes a key it didn't declare, that's a bug to fix, not a permission to enforce at runtime.
- **Append-friendly for lists**: when fan-out nodes all write to the same key (e.g., `reviews`), use append semantics. The graph coordinator handles concurrent appends.
- **Initial state**: `state.initial` seeds the keys that exist before the first node runs. All other keys are created by the node that first writes them.

## Define Interview

Walk the user through these 6 questions. Refuse to write `graph.yaml` until all answered. Covers 6 of the 8 checklist items in `rules/graph-engineering.md`; items 6 (isolate failure) and 7 (pick framework) are enforced by schema validation, not the interview.

1. **Have you tried a loop first?** Can a single agent with a good verifier do this? If yes, stop — use `/keep:loop`.
2. **Name the nodes.** What are the real specialties? Each must have a job a loop couldn't hold (different model, different toolset, or read-only reviewer). "Steps I could inline" are not nodes.
3. **Draw the edges.** What's sequential, what fans out, what fans in, where's the conditional/loop-back? If you can't draw it on a napkin, simplify.
4. **Design the state.** What object travels along the edges? Who reads what, who writes what?
5. **Does the reviewer have teeth?** Is there a dedicated reviewer node with a different model class, read-only input, and adversarial instructions?
6. **What's the budget?** `max_tokens` and `max_iterations`. Graphs burn tokens in parallel — cap it.

## Validate Before Writing Spec

Refuse to write `graph.yaml` if the spec is malformed. Silent failure modes are unacceptable.

- **Node names unique**: no two nodes share a name.
- **Edges reference real nodes**: every `from`/`to` matches a declared node name.
- **At least one exit**: there must be a path from entry to a node with no outgoing edges (or a conditional `when: pass` to exit).
- **Skill refs exist**: if a node declares `skill: <name>`, `Glob skills/*/SKILL.md` must match it. If absent, surface closest matches and ask the user.
- **No cycles without exit**: if there's a loop-back edge, verify `budget.max_iterations` is set (otherwise infinite loop).

## Resource Check (run start)

| Primitive | How to check |
|-----------|--------------|
| `Agent` | Agent tool available (always true in Claude Code) |
| `EnterWorktree` | tool exists (required for type=sprint nodes) |
| `mcp__mind__remember` | mind MCP reachable (for cross-graph synthesis) |
| Node `skill` refs | validated at `define` time; re-confirm here |

If a primitive is missing, surface which one and halt. Do not fall back silently.

## PR Review Graph — Worked Example

A complete, copy-pasteable `graph.yaml` for multi-perspective PR review:

```yaml
name: pr-review
description: Multi-perspective PR review with conditional ship/loop-back

state:
  initial:
    pr_url: ""           # set at run time
    diff: null
    reviews: []          # append-friendly: fan-out nodes append here
    verdict: null        # synthesis output: pass | fail

nodes:
  - name: fetch_diff
    type: agent
    model: haiku
    prompt: "Fetch the diff for {{state.pr_url}}. Write raw diff to state.diff."
    input: [pr_url]
    output: [diff]

  - name: security_review
    type: agent
    model: opus
    skill: /keep:review
    prompt: "Security lens on {{state.diff}}: attack surface, auth, data flow. Verdict pass/fail."
    input: [diff]
    output: [reviews]

  - name: architecture_review
    type: agent
    model: opus
    skill: /keep:review
    prompt: "Architecture lens on {{state.diff}}: module depth, seams, coupling. Verdict pass/fail."
    input: [diff]
    output: [reviews]

  - name: tests_review
    type: agent
    model: opus
    skill: /keep:review
    prompt: "Tests lens on {{state.diff}}: coverage, edge cases, integration. Verdict pass/fail."
    input: [diff]
    output: [reviews]

  - name: synthesis
    type: agent
    model: opus
    prompt: "Read {{state.reviews}}. Synthesize into one verdict: pass if all reviewers pass, fail with specifics otherwise."
    input: [reviews]
    output: [verdict]

edges:
  # Fan-out: fetch → 3 parallel reviewers
  - from: fetch_diff
    to: [security_review, architecture_review, tests_review]

  # Fan-in: 3 reviewers → synthesis (waits for all)
  - from: [security_review, architecture_review, tests_review]
    to: synthesis

  # Conditional: synthesis passes → exit (ship)
  #              synthesis fails → loop back to fetch_diff (after fixes)
  - from: synthesis
    to: fetch_diff
    when: fail

budget:
  max_tokens: 200000
  max_iterations: 3            # max 3 review rounds
```

Note: the `synthesis → exit when: pass` path is implicit — when synthesis returns `verdict: pass` and no `when: fail` edge fires, the graph exits.
