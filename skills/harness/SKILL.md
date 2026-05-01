---
name: keep:harness
description: Harness component management. TRIGGER when: modifying hooks, rules, skills, settings.json, install.sh, or evaluating harness architecture. Do NOT trigger for: normal coding tasks, bug fixes in non-harness code, or general questions.
resources: ['git', 'settings-json']
---

# Harness Component Management

## Hook Lifecycle Discipline

- Hooks map to lifecycle events: PreToolUse → PostToolUse → PreCompact → Stop
- PreToolUse (safety): block/warn destructive commands before execution (safety-guard)
- PreToolUse (rewrite): transparent command optimization (nto-rewrite)
- PostToolUse (validation): available for file state verification after writes
- PreCompact (compaction): inject compaction priorities to preserve critical context
- Stop (session state): fires on session end for cleanup, audit, or handoff reminders
- Hook failure is non-blocking — guards assist, they must never paralyze
- New hooks: add to settings.json under the correct lifecycle event, test in isolation first

## Harness Component Lifecycle

Harness components (hooks, rules, skills) have different expiry speeds across model upgrades. What Opus 4.5 needed, Sonnet 4.6 may handle natively.

### Review Cadence
- After every model upgrade: re-evaluate all hooks, rules, and skills for continued value
- Quarterly: prune components that no longer measurably improve output quality

### Pruning Criteria
- **Remove** if: model now handles the case natively (e.g., safety refusals without safety-guard)
- **Remove** if: the rule adds more context cost than quality improvement it provides
- **Simplify** if: a 20-line rule can be replaced by a 2-line reminder
- **Keep** if: benchmark shows measurable quality delta with vs without the component

### Accumulation Anti-Pattern
- Adding rules without removing old ones = context bloat = degraded performance
- Every new component must justify its token cost against the quality improvement
- Prefer fewer, high-impact rules over many narrow ones

## Adding New Components

1. Write the component (hook script, rule file, or skill)
2. Test in isolation before integrating
3. Register in settings.json (hooks) or place in correct directory (rules, skills)
4. Update install.sh if hook needs deployment
5. Run `python3 scripts/benchmark.py --quick` to verify no regression
6. Document purpose and expected value in commit message

## Gotchas (Non-Obvious Failure Modes)

### Memory Index Cap
- mind index files must stay under 200 lines / 25KB — exceeding this makes memory a liability (more tokens wasted than value returned)
- Split large indexes into topic-specific files; enforce cap via `dream_cycle(prune)`

### Derivable Content Never Stored
- Never store in memory what can be derived from code (function signatures, file lists, type definitions)
- Memory is for decisions, corrections, preferences — not for searchable facts
- Test: "Can I get this from `grep` or `smart_search`?" → If yes, don't store it

### Fork Recursion Guard
- Subagents spawning subagents must have a depth limit (max 2 levels)
- Without guard: exponential context cost, timeout cascades, stale references
- Pattern: pass `--max-depth N` or check parent context before delegating
