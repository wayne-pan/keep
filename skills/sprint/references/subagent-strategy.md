# Subagent Strategy Reference

Patterns for effective subagent orchestration.

## Core Principles

- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One task per subagent for focused execution

## Output Discipline

- **Output limit**: Tell subagents "Return only key conclusions and file paths, under 200 words"
- **Prefer structural tools**: Instruct subagents to use `smart_outline`/`smart_search` over full file reads
- After each subagent completes: discard raw output, keep only conclusions

## Parallel Execution Patterns

### Research Phase
Spawn 2-3 subagents in parallel, each exploring a different code path or module:
```
Subagent 1: "Trace authentication flow from entry to DB. Return file paths and key functions, under 200 words."
Subagent 2: "Map data model and schema relationships. Return table names and foreign keys, under 200 words."
Subagent 3: "Find all error handling patterns. Return file paths and patterns found, under 200 words."
```

### Implement Phase
One module per subagent, each with clear target files:
```
Subagent A: "Implement X in src/module_a.py. Follow plan section 3.1. Return only what changed, under 200 words."
Subagent B: "Implement Y in src/module_b.py. Follow plan section 3.2. Return only what changed, under 200 words."
```

### Review Phase
Spawn bug hunter + security auditor with different lenses (see `/keep:review` skill).

## Anti-Patterns

- Don't spawn subagents that read the same files — coordinate targets
- Don't let subagents write to the same files — partition by module
- Don't pass full file contents to subagents — give them file paths and let them read
- Don't summarize subagent output twice — once in main context is enough
