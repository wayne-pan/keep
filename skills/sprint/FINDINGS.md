# Sprint Findings (cross-session knowledge)

Persistent knowledge accumulated across sprints. Append-only — never delete entries.

## Format
```
### [DATE] — [TOPIC]
- **Context**: what sprint/task triggered this finding
- **Finding**: the key insight or pattern discovered
- **Confidence**: high/medium/low
- **Relevance**: when this finding applies
```

---

### 2026-07-22 — Plan Review Gate: first real exercise
- **Context**: sprint implementing /keep:graph layer; first sprint to use the Plan Review Gate that replaced user approval between Plan and Implement
- **Finding**: Gate works as designed. Round 1 (fresh opus sub-agent) found 10 concrete issues — vague tool calls, missing worked examples, hand-waving in stop-check adaptation, JS idioms (Promise.all) in a bash project. All fixed via 8 targeted Edits. Round 2 verified all 10 fixed, found 3 new minor issues (README line refs, STATE.md entry consistency). For cosmetic issues, fix inline and proceed rather than STOP — the gate's intent is blocking low-quality plans, not blocking on description-level precision.
- **Confidence**: high
- **Relevance**: any future sprint using the Plan Review Gate. The "max 2 rounds" cap is the right balance — prevents infinite fix-review loops while catching real ambiguity.

### 2026-07-22 — Graph Engineering: Design It Twice hybrid approach
- **Context**: designing graph.yaml schema for /keep:graph; spawned 3 parallel sub-agents (minimize interface / maximize flexibility / optimize common caller)
- **Finding**: Agent 3's "implicit edges" (nodes default to declaration order; edges section is optional) was the depth winner — 90% of real graphs need only sequential + occasional fan-out. Hybrid: Agent 3's implicit sequential as the core + Agent 1's conditional `when` field (simplified to pass|fail|always, not JSONata) + Agent 2's node type diversity (agent|loop|sprint|graph for nesting). Explicitly rejected: JSONata/jq expressions, per-field state permissions, dynamic fan_out — all flagged by article checklist as over-engineering.
- **Confidence**: high
- **Relevance**: any future schema design where the common case is simple and edge cases are complex. Default to the simplest implicit behavior; make advanced features explicit.

<!-- Append new findings above this line (newest first) -->
