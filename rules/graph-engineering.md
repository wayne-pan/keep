# Graph Engineering

Coordinating multiple specialized agents into a wired system — nodes that do the work, edges that route between them, shared state flowing along the edges. Sits **one floor above loop engineering**. Coordinate, don't reimplement.

Use these terms exactly. Don't substitute "workflow," "pipeline," or "orchestration."

## The Stack

Five floors. Each floor wraps the one below. Cumulative — skip a lower layer and the graph on top fails in a more elaborate way.

| Floor | Layer | What lives here |
|-------|-------|-----------------|
| 5 | **Graph** | Coordination between many agents/steps. This layer. |
| 4 | Loop | One agent's repeat cycle — discover/plan/execute/verify. The inside of a node. |
| 3 | Harness | Skills, hooks, crons, MCP, worktrees, sub-agents — keep's own primitives. |
| 2 | Context | File contents, memory, diffs — what the model sees. |
| 1 | Prompt | The token sequence sent to the model. |

A graph floor composes loops (and other primitives) into a coordinated circuit. It adds **no** new primitive. If you are writing a new worktree / cron / memory / sub-agent shim, you are on the wrong floor.

Graph is the outermost layer. That makes it the one you should reach for **last**. Most work is still a loop.

## Terms

**Graph** — A network of nodes connected by edges, with shared state flowing between them. One graph = one coordinated workflow. _Avoid_: workflow, pipeline, orchestration.

**Node** — A unit that does work. Usually a specialized agent (researcher, writer, reviewer) or a deterministic step (fetch, format). Each node has one job. A node can itself be a `/keep:loop` — the loop is the inside of the node. _Avoid_: step, stage, component.

**Edge** — Routing between nodes. Says "after this node, go to that one." Can be straight (A→B), **conditional** (if verdict=pass, ship), **fan-out** (A→[B,C,D] in parallel), or **fan-in** ([B,C,D]→E, wait all). _Avoid_: connection, link, transition.

**Shared State** — The object that travels along edges. What every node reads from and writes to: the task, the draft so far, the verdicts. State is what turns a pile of agents into a system instead of a group chat that forgets everything. _Avoid_: context, payload, message.

**Revolution** — One completed traversal of the graph from entry to exit. Multiple revolutions = re-running the graph (e.g., after external trigger).

**Spec** — Declarative graph definition at `.graph/<name>/graph.yaml`. Edits to the spec are how you steer the graph — not edits to the harness.

**Verdict** — A node's pass/fail output, consumed by conditional edges. Reuses the loop evaluator's 4-key format: `{verdict, confidence, evidence, missing_checks}`.

## The Core Insight

**A loop is a single-node self-loop graph.** Everything you learned about designing loops — the discover/plan/execute/verify cycle, the stop condition, the verifier — is the inside of one node. A graph doesn't replace the loop. It's what you get when you have several loops that need to hand off to each other.

If your graph has one node with an edge back to itself, it's a loop. Use `/keep:loop` instead.

## When to Reach for a Graph

This is the load-bearing question. The default answer: **you probably don't.** A single well-scoped task with a clear verifier is a loop, and reaching for a graph there is pure overhead.

| Signal | Loop is enough | Reach for a graph |
|--------|---------------|-------------------|
| **Shape of the task** | One job with a clear finish line | Splits into distinct specialties that hand off |
| **Parallelism** | Steps are sequential | You need fan-out (many at once) then a join |
| **Tools/models per step** | Same throughout | Different model or toolset per step |
| **Control flow** | One agent can free-roam safely | You need explicit, auditable routing between roles |
| **Failure isolation** | A bad step just retries | You want one bad node to fail without poisoning the rest |
| **Who verifies** | The agent checks its own output | A dedicated reviewer node checks another node's work |

Read this table as a set of **triggers**, not a checklist. You don't need all six. But if the honest answer to most is the left column, building a graph turns a two-hour task into a two-day framework project.

### Anti-pattern: the org chart for an email

> "Summarize this PDF." You build a 5-node graph: fetcher, chunker, summarizer, reviewer, formatter. It works — and it's slower to build, harder to debug, and more expensive than one agent in a loop that reads the file and writes a summary. **You engineered an org chart to answer an email.**

The tell: if you can collapse your five nodes back into one agent's loop and lose nothing, you should.

## The Eight-Item Checklist

Before turning a loop into a graph, run the idea through this:

1. **Try to keep it a loop.** Can a single well-scoped agent with a good verifier do this? If yes, stop. You're done.
2. **Name nodes only if they're real specialties.** Each node should have a job a single loop couldn't hold — a different model, a different toolset, or a read-only reviewer role. "Steps I could inline" are not nodes.
3. **Draw edges before you code.** Sketch the routing: sequential, fan-out, fan-in, conditional. If you can't draw it on a napkin, it's too complex.
4. **Design shared state explicitly.** Decide what travels along edges and who's allowed to write to it. State drift is the #1 way graphs rot.
5. **Give the reviewer node teeth.** The highest-value node is usually a separate, read-only verifier — a different agent from the one that produced the work. This is the loop's "don't let an agent self-verify," promoted to a node.
6. **Isolate failure.** One node can fail and retry without corrupting shared state or poisoning downstream nodes.
7. **Pick a framework instead of hand-rolling.** keep's harness IS the framework — Agent, EnterWorktree, kv-*/mcp__mind__* are your nodes/edges/state primitives. Reinventing the runtime is its own kind of slop.
8. **Set a spend cap.** A graph is many loops; a weak verifier now burns tokens in parallel. Cap it.

## Graph vs Loop

Graph and loop are not alternatives. They compose.

- A graph's node can invoke `/keep:loop` as its implementation. The loop runs inside the node; the graph routes between nodes.
- Layering: **graph → loop → sprint**. Each layer orchestrates the one below.
- `/keep:loop` stays untouched. Graph is purely additive — a new way to wire existing primitives.
- Recurring execution = `/keep:loop` scheduling a graph invocation. Graph is one-shot coordination; loop is the recurring unit.

If the work is "do X repeatedly on a schedule," that's a loop (possibly one that invokes a graph each time). If the work is "coordinate these N specialties to produce this one artifact," that's a graph.

## Six Parts → keep Primitives

A graph is built from six parts. All six already exist as keep primitives.

| Part | Role | keep primitive |
|------|------|----------------|
| **Nodes** | Agents that do the work | `Agent` with model + skill + prompt |
| **Edges** | Routing + conditions | Declared in `graph.yaml` (to/from/when) |
| **State** | Shared object between nodes | `.graph/<name>/state.yaml` (single source of truth) |
| **Isolation** | Worktree per side-effecting node | `EnterWorktree` / `ExitWorktree` |
| **Evaluator** | Reviewer node with teeth | `Agent` (different model, adversarial prompt) |
| **Memory** | Cross-graph synthesis | `mcp__mind__remember` / `recall` |

Deletion test: delete the graph layer. The six parts still work; you just lost the coordinator. Complexity did not vanish — it reappeared as you, manually wiring sub-agents with pasted context. The layer earned its keep.

## Four Costs (amplified by parallelism)

A loop left to its own devices incurs four costs. A graph amplifies all four — parallel nodes mean more output to verify, more state to understand, more tokens burning at once.

| Cost | What happens (graph-amplified) | Countermeasure |
|------|--------------------------------|----------------|
| **Verification debt** | N reviewer nodes can rubber-stamp in parallel | Each reviewer is a different model class from the generator; synthesis node re-runs primary check independently |
| **Understanding rot** | State grows as it flows; nobody remembers who wrote what | `.graph/<name>/STATE.md` is the audit log; `input`/`output` arrays declare who reads/writes each key |
| **Cognitive surrender** | Graphs feel autonomous; you stop checking the verdicts | `human_checkpoint` on synthesis or ship nodes; budget cap forces re-entry |
| **Token runaway** | N nodes run in parallel; weak verifier burns N× tokens | `budget.max_tokens` + `budget.max_iterations` (hard cap on node spawns) |

If any cost is left uncountered, the graph is not engineered — it is abandoned.

## Prior Art & Skeptics

The mechanics are not new. Honest acknowledgment:

**Prior art** (got there before the buzzword):
- **LangGraph** (LangChain) — `StateGraph` of nodes and edges over shared state. If you've used it, you've been doing graph engineering under a different name.
- **Microsoft AutoGen GraphFlow** — graph-based multi-agent orchestration for AutoGen teams.
- **Google ADK** — sequential, parallel, and loop workflow agents as first-class building blocks.
- **A2A (Agent2Agent)** — open protocol for cross-system agent delegation; the "edges between graphs owned by different teams" layer.

**Skeptics** (they're right):
- @PawelHuryn: "skip mechanism-naming, give agent the objective, why it matters, and how success gets measured."
- @NathanFlurry: "A2A and IBM have been doing multi-agent delegation since 2025."
- @RhysSullivan: "there will be a 10,000-word slop article on graph engineering tomorrow."
- @DavidKPiano (XState creator): "directed graphs of states and transitions are decades-old computer science."

The label is optional. The escalation from one loop to a coordinated graph is real — just don't reach for it before you need it.

## Principles

- **One floor up.** If you are writing a new primitive, you are on the wrong floor.
- **Loop first.** A graph earns its keep only when a single loop genuinely cannot hold the work.
- **Spec, not code.** Steer by editing `.graph/<name>/graph.yaml`, not by patching the harness.
- **State is the contract.** Who-reads-who-writes is declared in `input`/`output` arrays. Undeclared state mutations are the #1 rot.
- **The reviewer is load-bearing.** A graph without a dedicated reviewer node (different model, read-only, adversarial) is an echo chamber with extra cost.
- **Napkin test.** If you can't draw the graph on a napkin, it's too complex. Simplify or split.
- **Deletion test.** Delete the graph layer. If complexity vanishes, it was a pass-through. If it reappears as manual coordination, it earned its keep.
