# Evaluator — Graph Adaptation

Full evaluator construction lives in `skills/loop/references/evaluator.md`. This file covers **only what's different for graphs**. Read that file first; this is a delta, not a standalone.

## Why Graphs Need Evaluators Differently

In a loop, there's one evaluator per revolution — it checks the generator's diff.

In a graph, every reviewer node IS an evaluator for its upstream node. The difference: a graph has **N evaluators running in parallel**, each checking a different slice of the work.

| Loop | Graph |
|------|-------|
| 1 evaluator per revolution | N reviewer nodes, each evaluating its upstream |
| Evaluator sees the whole diff | Each reviewer sees its lens (security / architecture / tests / ...) |
| One verdict → stop/continue | N verdicts → synthesis node aggregates |

## The Reviewer Node Pattern

A reviewer node is:
- `type: agent`
- **Different model class** from the generator node (if generator is sonnet, reviewer is opus — or vice versa)
- **Read-only input**: it reads state but its job is to evaluate, not to produce new content
- **Adversarial prompt**: "default prior: this is broken until proven otherwise"

```yaml
- name: security_review
  type: agent
  model: opus              # different from the writer's model
  skill: /keep:review
  prompt: "Security lens: attack surface, auth, data flow. Verdict pass/fail with evidence."
  input: [diff]            # read-only — reviews the diff, doesn't modify it
  output: [reviews]        # appends its verdict to the reviews list
```

## Reusing Loop's Verdict Format

Reviewer nodes return the same 4-key schema as loop evaluators:

```json
{
  "verdict": "pass" | "fail",
  "confidence": 0.0-1.0,
  "evidence": ["<cmd> → exit <code> | <output>", "file:line — what was checked"],
  "missing_checks": ["what should have been checked but wasn't"]
}
```

`missing_checks` non-empty downgrades `pass` to `fail`. The evaluator is graded on what it admits it didn't check.

## Conditional Edge Decision Rule

Edges with `when:` consume the verdict:

| Node verdict | Edge `when` | Edge fires? |
|--------------|-------------|-------------|
| `pass` | `pass` | ✅ |
| `pass` | `fail` | ❌ |
| `pass` | `always` | ✅ |
| `fail` | `pass` | ❌ |
| `fail` | `fail` | ✅ (loop-back) |
| `fail` | `always` | ✅ |

If no edge's `when` matches the verdict, the graph exits from that node (implicit success exit).

## Stop-Check Adaptation (synthesis node)

The synthesis node is the graph's equivalent of the loop's stop-check agent. It's the **third agent** in the maker-checker trio:

1. **Generator nodes** produced the work (security/architecture/tests reviews).
2. **Reviewer nodes** evaluated from their lenses.
3. **Synthesis node** reads all reviewer verdicts, re-runs the primary check independently, and decides the graph-level verdict.

The synthesis node:
- Reads all reviewer verdicts from state (`input: [reviews]`)
- Spawns a fresh `Agent(model=opus)` with the stop-check prompt skeleton from `skills/loop/references/evaluator.md`
- Returns `STOP` (graph exits → ship) / `CONTINUE` (loop-back edge fires → re-review) / `ESCALATE` (graph halts, human must intervene)
- **Has no shared context with the reviewer nodes** — it's a fresh agent with fresh instructions

This blocks the collusion pattern where N reviewers rubber-stamp each other in parallel.

## Anti-Patterns

- **Same agent reviews itself.** A node that generates work and then evaluates it in the same turn. Forbidden.
- **Reviewer shares model with generator.** A sonnet generator + sonnet reviewer = rubber stamp. Use a different model class.
- **Pass with empty evidence.** A verdict of `pass` must include what was checked and what was found. No evidence = no pass.
- **No fan-in before synthesis.** If the synthesis node runs before all reviewers complete, it sees partial state. Fan-in is mandatory.
- **Synthesis node shares context with reviewers.** The synthesis node must be a fresh agent — if it remembers the reviewers' prompts, it inherits their biases.

## When to Escalate

`ESCALATE` from the synthesis node halts the graph:
- No further nodes run.
- STATE.md records the ESCALATE + evidence (audit trail).
- Human must re-arm via `/keep:graph run <name>` after addressing the issue.

Unlike `fail` (which triggers a loop-back), `ESCALATE` means "this graph cannot proceed safely — something is structurally wrong." Use it sparingly: the synthesis node should ESCALATE only when the reviewers contradict each other irreconcilably, or when evidence is missing in a way that can't be fixed by re-running.
