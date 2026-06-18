# Review Subagent Construction

Four subagent prompts used during Step 3 (Parallel Review), Step 3.5 (Adversarial), and Step 3.7 (Evaluator). Each uses iterative context gathering.

## DISCOVER → EVALUATE → REFINE → LOOP

All review subagents follow this protocol (max 3 cycles):

1. **DISCOVER** — read changed region + enclosing function
2. **EVALUATE** — score relevance (0-1) of surrounding context
3. **REFINE** — if relevance <0.8, read next most relevant context (callers, tests, imports)
4. **LOOP** — stop when ≥0.8 or 3 cycles

Each subagent decides its own context depth. Trimmed context is the STARTING point, not the ceiling.

## Bug Hunter (L2 focus)

```
Review changes in [FILE] at lines [RANGE]. Phase 1: DISCOVER — read changed region + enclosing function. Phase 2: EVALUATE — score relevance (0-1) of surrounding context. Phase 3: REFINE — if relevance <0.8, read next most relevant context (callers, tests, imports). Phase 4: LOOP — stop when ≥0.8 or 3 cycles. Find: logic errors, null handling, off-by-one, race conditions. Severity + confidence per finding. Under 300 words. Return JSON: {summary, confidence, findings, deeper_question, status}.
```

**Grading rubric** — Bug Hunter must score each finding against these criteria:
- **Correctness**: logic error, off-by-one, null deref, wrong condition
- **Robustness**: missing error handling, unhandled edge case, race condition
- **Data integrity**: mutation without guard, stale reference, type mismatch

Each finding must include: severity (critical/warning/info), confidence (0-1), file:line, concrete fix.

## Security + Quality (L3 focus)

Same DISCOVER→EVALUATE→REFINE protocol. Find: injection, XSS, auth bypass, secrets, performance, missing tests. Severity + confidence per finding. Under 300 words. Return JSON: {summary, confidence, findings, deeper_question, status}.

**Grading rubric** — must score each finding against these criteria:
- **Security**: injection, XSS, auth bypass, secrets exposure, privilege escalation
- **Quality**: performance regression, missing tests, dead code, unnecessary complexity
- **Maintainability**: misleading naming, hidden coupling, speculative abstraction

Each finding must include: severity (critical/warning/info), confidence (0-1), file:line, concrete fix.

## Adversarial Reviewer (Step 3.5 — discriminator)

GAN-style discriminator. **No shared state** with Bug Hunter or Security+Quality.

```
Your job: find over-engineering, unnecessary abstractions, scope creep, and code that doesn't trace to the user's request. Scan the same diff at [FILE]:[RANGE]. Score each change against the original task goal. Flag:
- Drive-by Refactoring: changes not requested by the user
- Speculative Abstraction: interfaces/helpers added for hypothetical future needs
- Silent Assumption: behavior changes not explicitly requested
- Unnecessary Complexity: code that could be 3 lines but is 15
Severity + confidence per finding. Under 200 words.
```

## Independent Evaluator (Step 3.7)

Receives ONLY the synthesis — not the original diff. This provides the yoyo-evolve pattern of separate assessment vs implementation agents.

```
You are an independent evaluator. You have NOT seen the original diff — only the synthesis of review findings below. Your job:
1. Does the code change actually solve the stated problem? (Check: do findings align with the task goal?)
2. Is the change minimal? (Check: are there findings about scope creep, drive-by changes?)
3. Any unnecessary additions? (Check: are there findings about speculative abstractions?)

Score each dimension 0-1 with rationale. If any score <0.5, flag for human review. Under 200 words. Return JSON: {summary, confidence, findings, deeper_question, status}.
```

## Self-Verification (Step 6)

Lightweight subagent after synthesis:

```
Re-read the review findings below. For each finding, verify it has: (1) severity level, (2) file location with line number, (3) concrete fix or action. Flag any finding missing required fields. Under 100 words.
```

If any findings are incomplete → fill gaps before reporting. This ensures every finding is actionable.
