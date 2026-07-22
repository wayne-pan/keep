# Node Execution Detail

Each node maps to an existing primitive. The graph coordinator reads `graph.yaml`, builds an adjacency list, and traverses from the entry node.

## Execution Model

1. Read `.graph/<name>/graph.yaml`.
2. Validate spec (see `spec-schema.md` → Validate Before Writing Spec).
3. Initialize state: write `state.initial` to `.graph/<name>/state.yaml`.
4. Determine entry node: the first node in `nodes` with no incoming edges (or the first node in declaration order if no edges section).
5. Traverse: execute each node per the Edge Traversal rules below.
6. On exit (no more edges to follow, or `when: pass` with no matching edge): write final state + verdict to `.graph/<name>/STATE.md`.

## Node Execution Protocol

For each node, the coordinator:

1. **Read input keys**: `Read` `.graph/<name>/state.yaml`, extract keys listed in `node.input`.
2. **Spawn the agent**: per the node's `type` (see Node Type Details below).
3. **Await completion**: the Agent call is synchronous — it returns before the coordinator proceeds.
4. **Write output keys**: extract fields from the agent's return JSON matching `node.output` keys; `Edit` `.graph/<name>/state.yaml` to update them.
5. **Return verdict**: the agent's `{verdict, confidence, evidence}` is recorded for conditional edge evaluation.

## Edge Traversal

How the coordinator moves between nodes:

- **No edges section**: nodes run in declaration order. After node N completes, proceed to node N+1. After the last node, exit.
- **With edges section**: the edges section fully replaces declaration order.
  - **Straight** (`from: A, to: B`): after A completes, proceed to B.
  - **Conditional** (`from: A, to: B, when: pass`): after A completes, check A's verdict. If it matches `when`, proceed to B. If no edge's `when` matches, exit.
  - **Fan-out** (`from: A, to: [B, C, D]`): after A completes, issue B, C, D as N `Agent` tool calls in a **single response**. The harness executes them in parallel. All N must return before the coordinator proceeds — this is the join.
  - **Fan-in** (`from: [B, C, D], to: E`): E starts only after B, C, D have all completed. The harness's parallel tool-call completion IS the join mechanism — no explicit `wait` needed.

**Budget check before each node spawn**: count iterations (total node spawns so far). If `iterations >= budget.max_iterations`, halt with reason `iterations_exceeded`.

## Node Type Details

Concrete invocation + output capture per type:

### `agent`
```python
if node.skill:
    Agent(model=node.model, skill=node.skill, prompt=render(node.prompt, state))
else:
    Agent(model=node.model, prompt=render(node.prompt, state))
```
- **Skill**: if `node.skill` is set (e.g. `/keep:review`), the Agent invokes that skill with the node's prompt as context. The skill provides structure; the prompt provides the specific lens.
- **Output**: agent's return JSON. Extract fields matching `node.output` keys, write to state.
- **Verdict**: from agent's return `{verdict: "pass"|"fail", confidence, evidence}`.

### `loop`
```python
Agent(prompt=f"/keep:loop run {node.skill}")
# Await completion (synchronous sub-agent).
Read(f".loop/{node.skill}/STATE.md")  # last revolution entry
```
- **Output**: read `verdict` + `artifacts` from the last revolution entry in the loop's STATE.md. Map to this node's `output` keys.
- **Verdict**: the loop's stop-check verdict (STOP → pass, ESCALATE → fail).

### `sprint`
```python
worktree = EnterWorktree(name=f"graph-{graph_name}-{node.name}")
Agent(prompt="/keep:sprint build", cwd=worktree)
# Await.
Bash(f"git -C {worktree} diff HEAD")  # capture the change
```
- **Output**: diff summary (files changed, lines added/removed). Map to this node's `output` keys.
- **Verdict**: `pass` if sprint completed + Quality Gate passed; `fail` if sprint halted or Quality Gate failed.
- **Cleanup**: `ExitWorktree(action="keep")` — preserve the worktree for review; user decides when to remove.

## Shared State Backend

`.graph/<name>/state.yaml` is the **single source of truth** for shared state. No second state mechanism — state lives here and only here.

- **Reads**: nodes read their `input` keys via the `Read` tool on `state.yaml`.
- **Writes**: nodes write their `output` keys via the `Edit` tool (append for lists, replace for scalars).
- **Fan-out write serialization**: when N nodes run in parallel (fan-out) and all write to the same key (e.g., appending to `reviews`), the coordinator collects all N outputs first, then merges them into state.yaml in a single Edit. This avoids concurrent-edit conflicts — the Edit tool is not transactional.
- **Cross-graph synthesis**: for facts that should persist beyond one graph run (lessons learned, patterns discovered), use `mcp__mind__remember`. These survive graph completion and are available to future graph runs.

## Failure & Halt

| Condition | Action |
|-----------|--------|
| Node fails (agent returns error) | Halt graph, write error to STATE.md. User decides whether to retry manually. |
| `max_iterations` exceeded | Halt with reason `iterations_exceeded`. |
| `max_tokens` exceeded (when measurable) | Halt with reason `budget_exceeded`. |
| Two same-type nodes fail in a row | Halt (pattern indicates systemic issue). |
| Human checkpoint node reached | Pause. Write "awaiting human — resume with `/keep:graph run <name>`" to STATE.md. |

On any halt: write halt reason to STATE.md. Do not silently skip.

## Persistence

Append to `.graph/<name>/STATE.md` per revolution:

```markdown
## Revolution <N> — <ISO date>
- entry: <node-name>
- nodes_run: <list>
- verdicts: {node-name: pass|fail, ...}
- final_state: {key: value, ...}
- tokens_spent: <n | "unavailable — see harness session report">
- halt_reason: <if halted, else none>
- artifacts: <worktree paths or PR URLs>
```

State file is the only cross-revolution memory the graph relies on. Memory MCP (`mcp__mind__remember`) is for synthesis-worthy facts only — not for in-flight state.
