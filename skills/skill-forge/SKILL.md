---
name: keep:skill-forge
version: "1.2"
triggers: ["/keep:create skill", "/keep:new skill", "/keep:save as skill", "/keep:skill", "/keep:make a skill", "/keep:turn this into a skill", "/keep:remember this pattern", "/keep:save this workflow"]
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
routes_to: ["dependency-skill"]       # optional, see Frontmatter Semantics
description: >
  [What it does]. TRIGGER when: [specific scenarios].
  Do NOT trigger for: [exclusion scenarios].
resources: ['resource1', 'resource2']
---
```

## Frontmatter Semantics

- **`name`** — `keep:<kebab-case>`. Matches the directory name under `skills/`.
- **`version`** — Semver string. Bump on structural change to the skill body.
- **`triggers`** — Slash-command forms only (`/keep:phrase`). Each trigger must be specific enough to not swallow other skills' triggers (no bare `/keep:make`, `/keep:create`, `/keep:write` — use `/keep:make a feature` etc.).
- **`description`** — One paragraph. Should include `TRIGGER when:` and `Do NOT trigger for:` clauses so the harness can route activation. Auto-trigger skills (empty `triggers:` array, e.g. `cross-review`) are exempt — they fire on lifecycle events, not user invocation. Read by the harness for routing, not the user.
- **`routes_to`** — **Capability declaration, not recursive invocation.** Lists skills this one *can* hand off to (typically via `routes_to` in the description prose: "use `/keep:review` for X"). It does **not** mean the skill auto-calls them on completion. Mutual `routes_to` (e.g. `sprint ↔ review`) is permitted — it just means each can reference the other, not that they form an infinite loop.
- **`resources`** — External primitives the skill relies on (`git`, `subagents`, `mind`, `cron`, `worktrees`, `git-diff`, `settings-json`). Listed so the skill can do a resource check at start and degrade gracefully.
- **`allowed-tools`** — Optional. Restrict which tools the skill may use (e.g. `Bash(browser-use:*)`).

## Invocation Mode (binary choice, mandatory)

Every skill is one of two modes. Pick at creation time and reflect it in `triggers` + `description`:

| Mode | Markers | When to use |
|------|---------|-------------|
| **user-invoked** | Non-empty `triggers:` array; description focuses on what the user types | The skill orchestrates a workflow the user consciously chooses (`sprint`, `grilling`, `route`). Zero automatic context load on other turns. |
| **model-invoked** | `triggers: []` (auto-trigger) OR rich `TRIGGER when:` clauses in description; the harness fires it on contextual match | The skill holds reusable discipline the agent should reach for whenever the task fits (`cross-review` on lifecycle events, hypothetical inline skills on keyword match). Costs context load on every conversation. |

**Rules:**

- A user-invoked skill **may** invoke model-invoked skills (`sprint` calls `tdd`'s vocabulary), but never another user-invoked one directly — route through the user.
- When in doubt, prefer **user-invoked**. The cost of "user has to type `/keep:X`" is far lower than the cost of "agent fires X on every conversation that mentions a keyword".
- If a directory has more than ~10 user-invoked skills, add a router (`/keep:route` pattern) — don't expect users to memorise the catalog.

## Body Sections (in order)

1. **Title + one-line purpose**
2. **Trigger** — when to activate (verbatim phrases + contextual cues)
3. **Protocol** — numbered steps with concrete file paths, commands, line refs
4. **Quality checks** — how to verify output is correct
5. **Examples** — 1-2 good/bad output pairs showing what correct usage looks like
6. **Safety** — what NOT to do, edge cases to avoid

## Leading Words (reuse before redefining)

Models come pre-trained on compact concepts. A single leading word — _deep module_, _seam_, _adapter_, _tracer bullet_, _red-green_, _locality_, _leverage_ — anchors more behaviour than a paragraph of prose. One token stands in for a page.

**Before drafting a new skill:**

- [ ] Read `rules/architecture-language.md` for the canonical glossary (module, interface, implementation, depth, seam, adapter, leverage, locality).
- [ ] `Grep` existing `skills/*/SKILL.md` for words already load-bearing in this repo.
- [ ] Reuse those terms verbatim. Do not coin synonyms (`component`, `service`, `API`, `boundary`, `unit` are all banned substitutes — see `rules/architecture-language.md`).
- [ ] Only invent new vocabulary when no existing term fits — and when you do, propose it for addition to `rules/architecture-language.md` so the next skill inherits it.

**Example.** Instead of:

> "Design the module so that callers don't need to know much, but it does a lot of work behind the scenes."

Write:

> "Design a **deep module** — small interface, deep implementation."

Same behaviour anchored in 4 tokens instead of 24.

## Failure Modes (named, diagnostic, not complaints)

Every skill ages. These are the five ways skills die — name them when patching so the fix is targeted, not cosmetic.

| Mode | Symptom | Fix |
|------|---------|-----|
| **premature completion** | Skill declares done before its `Done when:` criteria are actually met | Tighten the checklist; add a hard gate (`diagnosing-bugs` Phase 1 is the template) |
| **sediment** | Lines accumulate that no longer change default behaviour — old examples, dead branches, retired edge cases | Run the no-op test below; delete what fails it |
| **sprawl** | Skill grows past its original trigger surface, swallowing neighbouring skills' jobs | Split or narrow; restore the trigger contract |
| **duplication** | Two skills cover the same ground — neither is the canonical home | Pick one, `routes_to` the other, delete the loser's body |
| **no-op** | A sentence that, if deleted, changes nothing about the agent's behaviour | Delete it. Now. |

The first four are diagnosed against the skill's *history*; the last is diagnosed against each sentence *in isolation*.

## The No-op Test (run on every draft, sentence by sentence)

For each sentence in the draft, ask:

> "If I delete this, does the agent's behaviour on the next run change?"

- **Yes** → keep it; the sentence earns its tokens.
- **No** → delete it. It's sediment waiting to happen.
- **Maybe** → rewrite it as a concrete instruction, or delete it.

Common no-ops to cut on sight:

- Restatements of the title ("This skill does X." when the title already says it)
- Generic platitudes ("Communication is key." "Be careful.")
- Definitions of well-known terms (don't redefine _test_ in a TDD skill)
- Aspirational guidelines with no observable consequence ("Strive for clarity.")
- Marketing copy ("This powerful workflow…")

**Exceptions**: title purpose line, `Done when:` criteria, explicit prohibitions (`DO NOT`, `Never`). These change behaviour even when they look like platitudes — because the absence of a prohibition is permission.

## Creation Flow

1. **Evaluate** — does this meet trigger conditions? If no, stop.
2. **Search** — `mcp__mind__search` for recurrence. `Glob skills/*/SKILL.md` for overlap.
3. **Draft** — write SKILL.md using template. Stay within the type ceiling (see Size Discipline below). Include at least one example pair.
   - Pick invocation mode (user-invoked vs model-invoked) before writing the body.
   - Reuse leading words from `rules/architecture-language.md` and existing skills.
4. **No-op test** — read every sentence; delete the ones that fail.
5. **Validate** — check Quality Gate below.
6. **Deploy** — create `skills/[name]/SKILL.md` in project repo.

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
- [ ] Total length within type ceiling (Reference ≤80, Action ≤100, Orchestrator ≤250 — see Size Discipline)
- [ ] No derivable content — only procedure, not facts
- [ ] Invocation mode picked (user-invoked vs model-invoked) and reflected in `triggers` + `description`
- [ ] Leading words reused from `rules/architecture-language.md` where applicable; no banned synonyms (`component`, `service`, `API`, `boundary`, `unit`)
- [ ] No-op test passed — every surviving sentence changes behaviour when deleted
- [ ] No active failure mode (premature completion / sediment / sprawl / duplication / no-op)

## Size Discipline

Skills are prompts — every line costs tokens on every activation. But skill *type* sets the natural ceiling.

**The numbers below are guidelines, not laws.** They're calibrated against existing skills in this repo (largest orchestrator: triage at 230 lines; largest reference: cross-review at 57). Treat a ceiling crossing as a trigger to ask "why is this long?", not as an automatic refactor.

| Skill type | Guideline | Why |
|------------|-----------|-----|
| **Reference** (vocabulary, glossary, rules) | ~80 lines | Pure lookup; progressive-disclose to references/ aggressively |
| **Action** (single-shot procedure: `deslop`, `onboard`) | ~100 lines | One protocol, few branches |
| **Orchestrator** (multi-phase workflow with templates: `sprint`, `triage`, `handoff`, `to-prd`, `to-issues`, `prototype`, `architecture-scan`, `route`, `loop`, `grilling`, `teach`, `diagnosing-bugs`, `ubiquitous-language`, `review`, `ambient` — non-exhaustive) | ~250 lines | Phases × gates × templates naturally stack; splitting a workflow across references/ breaks flow |

Hard rules (these are laws):

- **Under 50 lines**: ideal (any type)
- **Over 250 lines**: too heavy even for orchestrators — refactor (extract a sub-skill, prune no-ops) or remove

When an orchestrator crosses its guideline (~150+), the trigger is *not* "split by default" but "audit for no-ops and templates that can be pushed to references/". A workflow skill with 8 phases × 3-line gate each is legitimately ~150 lines; a reference skill at 150 lines is broken. The audit is the discipline, not the line count.
