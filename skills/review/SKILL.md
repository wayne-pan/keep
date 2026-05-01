---
name: keep:review
version: "1.2"
triggers: ["/keep:review", "/keep:code review", "/keep:check code", "/keep:audit", "/keep:inspect", "/keep:look at", "/keep:what do you think of", "/keep:is this safe", "/keep:any issues", "/keep:find bugs", "/keep:spot problems"]
routes_to: ["sprint"]
description: >
  Cross-validated code review using parallel subagents. TRIGGER when: the user asks
  for code review, says /keep:review, asks to audit/check/inspect code, or during sprint
  Review phase. Also trigger for "is this safe", "/keep:any issues", "/keep:find bugs", "/keep:what do
  you think of this code". Spawns multiple subagents with different review perspectives,
  then synthesizes findings. Do NOT trigger for: trivial changes, single-file edits,
  or when user just wants a quick glance.
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

### Step 3: Parallel Review (iterative retrieval)

Spawn subagents with **iterative context gathering** — they discover what they need:

**Protocol**: DISCOVER → EVALUATE → REFINE → LOOP (max 3 cycles)

**Bug Hunter** (L2 focus): "Review changes in [FILE] at lines [RANGE]. Phase 1: DISCOVER — read changed region + enclosing function. Phase 2: EVALUATE — score relevance (0-1) of surrounding context. Phase 3: REFINE — if relevance <0.8, read next most relevant context (callers, tests, imports). Phase 4: LOOP — stop when ≥0.8 or 3 cycles. Find: logic errors, null handling, off-by-one, race conditions. Severity + confidence per finding. Under 300 words. Return JSON: {summary, confidence, findings, deeper_question, status}."

**Grading rubric** (Bug Hunter must score each finding against these criteria):
- Correctness: logic error, off-by-one, null deref, wrong condition
- Robustness: missing error handling, unhandled edge case, race condition
- Data integrity: mutation without guard, stale reference, type mismatch
Each finding must include: severity (critical/warning/info), confidence (0-1), file:line, concrete fix.

**Security + Quality** (L3 focus): Same DISCOVER→EVALUATE→REFINE protocol. Find: injection, XSS, auth bypass, secrets, performance, missing tests. Severity + confidence per finding. Under 300 words. Return JSON: {summary, confidence, findings, deeper_question, status}.

**Grading rubric** (Security+Quality must score each finding against these criteria):
- Security: injection, XSS, auth bypass, secrets exposure, privilege escalation
- Quality: performance regression, missing tests, dead code, unnecessary complexity
- Maintainability: misleading naming, hidden coupling, speculative abstraction
Each finding must include: severity (critical/warning/info), confidence (0-1), file:line, concrete fix.

Each subagent decides its own context depth. Trimmed context is the STARTING point, not the ceiling.

### Step 3.5: Adversarial Review (discriminator)

Spawn a subagent with the **inverted goal** — push back against the generator's natural tendency toward safe/verbose output:

**Adversarial Reviewer**: "Your job: find over-engineering, unnecessary abstractions, scope creep, and code that doesn't trace to the user's request. Scan the same diff at [FILE]:[RANGE]. Score each change against the original task goal. Flag:
- Drive-by Refactoring: changes not requested by the user
- Speculative Abstraction: interfaces/helpers added for hypothetical future needs
- Silent Assumption: behavior changes not explicitly requested
- Unnecessary Complexity: code that could be 3 lines but is 15
Severity + confidence per finding. Under 200 words."

This is the GAN-style discriminator — it has NO shared state with Bug Hunter or Security+Quality subagents.

### Step 3.7: Independent Evaluator

After Bug Hunter + Security+Quality + Adversarial run, spawn an **Evaluator** subagent with ONLY the synthesis — not the original diff. This provides the yoyo-evolve pattern of separate assessment vs implementation agents.

**Evaluator**: "You are an independent evaluator. You have NOT seen the original diff — only the synthesis of review findings below. Your job:
1. Does the code change actually solve the stated problem? (Check: do findings align with the task goal?)
2. Is the change minimal? (Check: are there findings about scope creep, drive-by changes?)
3. Any unnecessary additions? (Check: are there findings about speculative abstractions?)

Score each dimension 0-1 with rationale. If any score <0.5, flag for human review. Under 200 words. Return JSON: {summary, confidence, findings, deeper_question, status}."

### Step 4: Self-Review (L1 + L4)
Run L1 syntax/basics scan while subagents work:
- Syntax check every changed file (bash -n, python ast, node --check)
- Scan for debug artifacts, hardcoded secrets, broken imports
- Quick check for dead code in diff

Then read diff + enclosing functions for L4 holistic quality.

### Step 5: Synthesize
Merge all three sources. Deduplicate and classify:
- **AUTO-FIX**: Obvious issues with high confidence → fix immediately
- **ASK**: Medium confidence OR high severity → present to user with options
- **FLAG**: Low confidence or speculative → note but don't block

Confidence gating:
- Both subagents agree → high confidence
- Only one flags → medium, downgrade to ASK or FLAG
- Self-review contradicts subagent → flag for user

### Step 6: Self-Verification
After synthesis, spawn a lightweight verification subagent:
"Re-read the review findings below. For each finding, verify it has: (1) severity level, (2) file location with line number, (3) concrete fix or action. Flag any finding missing required fields. Under 100 words."

If any findings are incomplete → fill gaps before reporting. This ensures every finding is actionable.

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

- `references/blast-radius.md` — Detailed impact tracing methodology
- `references/context-trimming.md` — Review-specific context cropping strategy
- `references/checklists.md` — Review checklist + anti-rationalizations
- `references/ideate.md` — Proactive codebase scan protocol (`/keep:review ideate`)
