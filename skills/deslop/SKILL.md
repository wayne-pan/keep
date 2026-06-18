---
name: keep:deslop
version: "1.0"
triggers: ["/keep:deslop", "/keep:cleanup slop", "/keep:remove boilerplate", "/keep:clean code"]
description: >
  Remove AI-generated code slop from recently changed files. TRIGGER when: user says
  /keep:deslop, "clean up slop", "remove boilerplate", or wants to strip unnecessary
  comments, defensive checks, wrapper functions, or debug artifacts from recent changes.
  Do NOT trigger for: general refactoring of untouched code, feature work, or style changes.
resources: ['git-diff']
---

# deslop

Remove AI-generated code slop from recently changed files.

## Instructions

1. Find recently modified files (use `git diff --name-only HEAD~1` or check working tree changes)
2. For each changed file, scan for these slop patterns:

### Remove
- **Unnecessary comments** that restate the obvious ("increment counter", "/keep:set timeout to 5000")
- **Redundant defensive checks**: guards that framework/language already guarantees
- **Unnecessary fallbacks**: `|| []`, `|| ''`, `|| {}` on operations that can't fail
- **Casts to `any`**: TypeScript `as any` used to bypass type system (fix the type instead)
- **Verbose error messages** that duplicate what the error type already conveys
- **Wrapper functions** that only call another function with no added logic
- **TODO/FIXME comments** that are vague ("clean this up later", "/keep:refactor")
- **Console.log/print statements** left from debugging
- **Unnecessary async/await** on synchronous operations
- **Double negations** (`!!` on already boolean values)

### Keep
- Comments explaining *why* (not *what*)
- Defensive checks at system boundaries (user input, external APIs)
- Type assertions that are genuinely needed (parse results, type narrowing)
- Error messages with actionable context

3. Apply fixes, then show a summary: "Removed N slop items from M files"

## Rules
- Only modify code that was recently changed (don't refactor untouched code)
- When removing a comment, ensure surrounding code is self-documenting
- If removal would change behavior, keep the code and note why
- Maximum 50 lines changed per invocation (avoid mass refactors)

## Examples

**Good removal** — comment restate the obvious:
```python
# Before
counter += 1  # increment counter
timeout = 5000  # set timeout to 5000

# After
counter += 1
timeout = 5000
```

**Bad removal** — comment explains *why*, must keep:
```python
# Before
timeout = 5000  # below 3s triggers provider rate limit; raised after incident 2024-11

# After (WRONG — context lost)
timeout = 5000
```

**Good removal** — redundant defensive check inside same module:
```typescript
// Before
const items = getItems();
const safe = items || [];  // getItems() always returns array per contract

// After
const items = getItems();
```

**Bad removal** — defensive check at system boundary, must keep:
```typescript
// Before
function handler(req: Request) {
  const body = req.body || {};  // external input — keep guard

// After (WRONG — req.body is untrusted)
function handler(req: Request) {
  const body = req.body;
```
