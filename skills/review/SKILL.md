---
name: keep:review
version: "1.3"
triggers: ["/keep:review", "/keep:code review", "/keep:check code", "/keep:audit", "/keep:inspect", "/keep:is this safe", "/keep:any issues", "/keep:find bugs", "/keep:spot problems"]
routes_to: ["sprint"]
description: >
  Cross-validated code review using parallel subagents. TRIGGER when: the user asks
  for code review, says /keep:review, asks to audit/check/inspect code, or during sprint
  Review phase. Also trigger for "is this safe", "any issues", "find bugs". Spawns
  multiple subagents with different review perspectives, then synthesizes findings.
  Do NOT trigger for: trivial changes, single-file edits, or when user just wants a quick glance.
resources: ['git-diff', 'subagents', 'mind']
---

# Cross-Validation Review

Independent code review from multiple subagent perspectives, synthesized into actionable findings.

## Protocol

### Step 1: Gather Changes

```bash
git diff --name-only HEAD~1  # or staged: git diff --cached --name-only
```

### Step 2: Blast Radius Analysis

Trace impact beyond the diff. For each changed symbol, find callers and dependents:

```bash
# Extract changed function/method names from diff
git diff HEAD~1 --unified=0 | grep -oE "(function \w+|def \w+|\w+\(\))" | sort -u
# Find callers of each changed symbol
grep -rn "symbol_name" --include="*.sh" --include="*.py" --include="*.js" .
# Find related tests
grep -rn "symbol_name" --include="*test*" .
```

Report blast radius before spawning subagents:

```
Blast Radius: func_a changed → 2 callers (func_b, func_c), 1 test, impact: MEDIUM
```

Detailed methodology: `references/blast-radius.md`.

### Step 3: Parallel Review (Bug Hunter + Security/Quality)

Spawn two subagents with iterative context gathering (DISCOVER → EVALUATE → REFINE → LOOP, max 3 cycles). Each subagent decides its own context depth.

- **Bug Hunter** (L2): logic errors, null handling, off-by-one, race conditions
- **Security + Quality** (L3): injection, XSS, auth bypass, secrets, performance, missing tests

Full prompts, grading rubrics, and JSON return contract: `references/subagents.md`.

### Step 3.5: Adversarial Review (discriminator)

Spawn a subagent with the **inverted goal** — push back against the generator's natural tendency toward safe/verbose output. Find: drive-by refactoring, speculative abstraction, silent assumptions, unnecessary complexity.

GAN-style discriminator — NO shared state with Step 3 subagents. Full prompt: `references/subagents.md`.

### Step 3.7: Independent Evaluator

After the three review subagents run, spawn an **Evaluator** with ONLY the synthesis — not the original diff. Checks: does the change solve the stated problem, is it minimal, are there unnecessary additions. Scores each dimension 0-1; flags any score <0.5 for human review.

Full prompt: `references/subagents.md`.

### Step 4: Self-Review (L1 + L4)

Run L1 syntax/basics scan while subagents work:

- Syntax check every changed file (`bash -n`, `python ast.parse`, `node --check`)
- Scan for debug artifacts, hardcoded secrets, broken imports
- Quick check for dead code in diff

Then read diff + enclosing functions for L4 holistic quality.

### Step 5: Synthesize

Merge all sources. Deduplicate and classify:

- **AUTO-FIX**: Obvious issues with high confidence → fix immediately
- **ASK**: Medium confidence OR high severity → present to user with options
- **FLAG**: Low confidence or speculative → note but don't block

Confidence gating:
- Multiple subagents agree → high confidence
- Only one flags → medium, downgrade to ASK or FLAG
- Self-review contradicts subagent → flag for user

### Step 6: Self-Verification

Lightweight subagent verifies every finding has: severity, file:line, concrete fix. Fill gaps before reporting. Full prompt: `references/subagents.md`.

### Step 7: Report

```
## Review Summary
- N findings (X critical, Y warning, Z info)
- Blast radius: [symbols changed → N callers, M tests]
- Auto-fixed: [list]
- Needs decision: [list with options]
- Verification: all findings checked for completeness
```

## Safety

- Never auto-fix architectural issues — always ask
- Never auto-fix security issues without showing before/after
- If no issues found, say so explicitly — don't fabricate problems
- Keep review focused on the diff + blast radius

## References

- `references/subagents.md` — Bug Hunter, Security+Quality, Adversarial, Evaluator, Self-Verification prompts and grading rubrics
- `references/blast-radius.md` — detailed impact tracing methodology
- `references/context-trimming.md` — review-specific context cropping strategy
- `references/checklists.md` — review checklist + anti-rationalizations
- `references/ideate.md` — proactive codebase scan protocol (`/keep:review ideate`)
