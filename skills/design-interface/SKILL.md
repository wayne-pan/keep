---
name: keep:design-interface
version: "1.0"
triggers: ["/keep:design interface", "/keep:design an interface", "/keep:design it twice", "/keep:interface design", "/keep:API design", "/keep:module shape", "/keep:compare designs"]
description: >
  Generate multiple radically different interface designs for a module using parallel
  sub-agents. TRIGGER when: user wants to design an API, explore interface options,
  compare module shapes, or mentions "design it twice", "/keep:interface design", "/keep:API design".
  Based on "Design It Twice" (Ousterhout) — your first idea is unlikely to be the best.
  Do NOT trigger for: implementing an already-designed interface, trivial single-method APIs.
resources: ['subagents']
---

# Design an Interface

Based on "Design It Twice" from _A Philosophy of Software Design_: your first idea is unlikely to be the best. Generate multiple radically different designs, then compare.

Uses the vocabulary from [rules/architecture-language.md](../../rules/architecture-language.md) — **module**, **interface**, **seam**, **adapter**, **depth**, **leverage**, **locality**.

## Workflow

### 1. Gather Requirements

Before designing, understand:

- [ ] What problem does this module solve?
- [ ] Who are the callers? (other modules, external users, tests)
- [ ] What are the key operations?
- [ ] Any constraints? (performance, compatibility, existing patterns)
- [ ] What should be hidden inside vs exposed?

Ask: "What does this module need to do? Who will use it?"

### 2. Frame the Problem Space

Before spawning sub-agents, write a user-facing explanation of the problem space:

- The constraints any new interface would need to satisfy
- The dependencies it would rely on, and which category they fall into (in-process, local-substitutable, remote but owned, true external — see [rules/architecture-language.md](../../rules/architecture-language.md))
- A rough illustrative code sketch to ground the constraints — not a proposal, just a way to make the constraints concrete

Show this to the user, then immediately proceed to Step 3. The user reads and thinks while the sub-agents work in parallel.

### 3. Generate Designs (Parallel Sub-Agents)

Spawn 3+ sub-agents simultaneously using the Agent tool. Each must produce a **radically different** approach.

```
Prompt template for each sub-agent:

Design an interface for: [module description]

Requirements: [gathered requirements]

Architecture language: [key terms from rules/architecture-language.md]
Domain language: [key terms from CONTEXT.md or UBIQUITOUS_LANGUAGE.md if they exist]

Constraints for this design: [assign a different constraint to each agent]
```

Assign one constraint per sub-agent:

| Agent | Constraint |
|-------|-----------|
| Agent 1 | "Minimize the interface — aim for 1-3 entry points max. Maximise leverage per entry point." |
| Agent 2 | "Maximise flexibility — support many use cases and extension." |
| Agent 3 | "Optimise for the most common caller — make the default case trivial." |
| Agent 4 | "Design around ports & adapters for cross-seam dependencies." |

Each sub-agent outputs:

1. **Interface** — types, methods, params, plus invariants, ordering, error modes
2. **Usage example** — how callers actually use it
3. **What it hides** — complexity kept internal behind the seam
4. **Dependency strategy** — adapters and seam placement
5. **Trade-offs** — where leverage is high, where it's thin

### 4. Present and Compare

Present designs sequentially so the user can absorb each one. Then compare them in prose on:

- **Depth** (leverage at the interface)
- **Locality** (where change concentrates)
- **Seam placement** (where adapters live)
- **Testability** (how tests cross the interface)

After comparing, give your own recommendation: which design you think is strongest and why. If elements from different designs would combine well, propose a hybrid. **Be opinionated** — the user wants a strong read, not a menu.

### 5. Synthesize

Often the best design combines insights from multiple options. Ask:

- "Which design best fits your primary use case?"
- "Any elements from other designs worth incorporating?"

## Evaluation Criteria

| Criterion | Good | Bad |
|-----------|------|-----|
| **Interface simplicity** | Fewer methods, simpler params | Many methods, complex params |
| **Depth** | Small interface hiding significant complexity | Large interface with thin implementation |
| **General-purpose** | Handles future use cases without changes | Over-generalized, abstract |
| **Implementation efficiency** | Shape allows efficient internals | Shape forces awkward internals |
| **Ease of correct use** | Default path is obvious, misuse is hard | Easy to misuse, many gotchas |

## Anti-Patterns

- Don't let sub-agents produce similar designs — enforce **radical difference**
- Don't skip comparison — the value is in contrast
- Don't implement — this is purely about interface shape
- Don't evaluate based on implementation effort
- Don't present a menu without a recommendation
