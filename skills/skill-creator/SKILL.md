---
name: keep:skill-creator
version: "1.0"
triggers: ["/keep:create skill", "/keep:new skill", "/keep:save as skill", "/keep:/skill", "/keep:make a skill", "/keep:turn this into a skill", "/keep:remember this pattern", "/keep:save this workflow"]
routes_to: ["harness"]
description: >
  Skill auto-creation and patching protocol. TRIGGER when: (1) completing a complex
  task (5+ tool calls, 2+ files), (2) overcoming iterative errors, (3) user-corrected
  approach worked, (4) user says /skill or "save as skill" or "turn this into a skill"
  or "remember this pattern" or "save this workflow", (5) pattern recurs across sessions
  (check memory). Do NOT trigger for: trivial edits, single-file changes, tasks covered
  by existing skills.
resources: ['mind']
---

# Skill Creator Protocol

Evaluate, create, and maintain `skills/*/SKILL.md` files.

## Trigger Matrix

After task completion, create if ANY condition is true:

| # | Condition | Evidence |
|---|-----------|----------|
| 1 | 5+ tool calls across 2+ files | Tool call count in session |
| 2 | Overcame 2+ errors before success | Iteration history |
| 3 | User corrected your approach, corrected version worked | Correction events |
| 4 | Same pattern found in 2+ past sessions | `mcp__mind__search` hits |
| 5 | User explicitly requests ("save as skill", "/keep:/skill") | Direct instruction |

## Anti-Triggers (do NOT create)

- Single file, <20 lines changed
- Already covered by existing skill (check `skills/*/SKILL.md` triggers)
- One-off task unlikely to recur
- Content derivable from documentation or code itself

## SKILL.md Template

```yaml
---
name: keep:[kebab-case, concise]
version: "1.0"
triggers: ["/keep:phrase1", "/keep:phrase2"]
routes_to: ["dependency-skill"]       # optional
description: >
  [What it does]. TRIGGER when: [specific scenarios].
  Do NOT trigger for: [exclusion scenarios].
resources: ['resource1', 'resource2']
---
```

Body sections (in order):
1. **Title + one-line purpose**
2. **Trigger** — when to activate (verbatim phrases + contextual cues)
3. **Protocol** — numbered steps with concrete file paths, commands, line refs
4. **Quality checks** — how to verify output is correct
5. **Examples** — 1-2 good/bad output pairs showing what correct usage looks like
6. **Safety** — what NOT to do, edge cases to avoid

## Creation Flow

1. **Evaluate** — does this meet trigger conditions? If no, stop.
2. **Search** — `mcp__mind__search` for recurrence. `Glob skills/*/SKILL.md` for overlap.
3. **Draft** — write SKILL.md using template. Keep under 100 lines. Include at least one example pair.
4. **Validate** — check Quality Gate below.
5. **Deploy** — create `skills/[name]/SKILL.md` in project repo.

## Auto-Patch Protocol

While using ANY skill, if you encounter:

- Step produces wrong output → patch the step immediately
- Missing edge case discovered → add it
- File path or line reference outdated → update it
- Better approach found → replace the inferior step

**Patch without asking.** Stale skills are liabilities.
Append version note: `<!-- patched YYYY-MM-DD: [reason] -->`

## Quality Gate

Every skill (new or patched) must pass:

- [ ] YAML frontmatter: name, version, triggers, description all present
- [ ] Triggers are non-overlapping with existing skills
- [ ] Steps reference concrete files/commands — not abstractions
- [ ] At least 1 good/bad output example demonstrating correct vs incorrect usage
- [ ] Total length < 100 lines (split into references/ if longer)
- [ ] No derivable content — only procedure, not facts

## Size Discipline

- Skills are prompts — every line costs tokens on every activation
- Under 50 lines: ideal
- 50-100 lines: acceptable, consider references/ for deep details
- Over 100 lines: mandatory split into SKILL.md + references/
- Over 150 lines total: too heavy — refactor or remove
