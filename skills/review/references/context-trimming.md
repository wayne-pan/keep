# Context Trimming for Review

Only send relevant code context to review subagents, not entire files. Inspired by code-review-graph's review-specific context cropping.

## Principle

Token budget for code review should be spent on the **change zone** and its immediate neighbors, not on unrelated code in the same file.

## Trimmed Context Strategy

### For Subagent Prompts

Instead of sending entire file content, extract only:

1. **Changed region**: ±10 lines around each diff hunk
2. **Function context**: The enclosing function/method (if change is inside one)
3. **Interface context**: Function signatures of callers/callees in blast radius

### Implementation

```bash
# Extract changed regions with context
git diff HEAD~1 -U10 -- changed_file.sh

# Extract just the enclosing function (shell)
awk "/^function.*\(/{found=0} /changed_function/{found=1} found{print; if(/^}/) exit}" file.sh

# Extract function signatures only (for callers)
grep -E "^(function |def |class |export |[a-zA-Z_]+\(\))" caller_files...
```

### What NOT to Send

- Import statements (unless they changed)
- Comments and docstrings (unless they're in the diff)
- Unchanged functions in the same file
- Test fixtures and setup code

## Subagent Prompt Template

Instead of: "Review these files: [FULL_FILE_CONTENTS]"

Use: "Review these changes in [FILE]:
- Changed: lines 15-30 (function `process_input`)
- Context: function reads config, validates input, calls `write_output`
- Callers: `main()` at line 80, `test_handler()` in tests/test_file.sh
- [DIFF OUTPUT]"

This reduces subagent input from potentially thousands of tokens to a few hundred.

## Iterative Retrieval Protocol

Subagents don't know what context they need until they start working. Solution: progressive refinement.

### Flow
1. **DISCOVER**: Read the changed region + enclosing function (given in prompt)
2. **EVALUATE**: Score relevance of available context (0.0-1.0)
   - 0.8-1.0: High — enough context, proceed to analysis
   - 0.5-0.7: Medium — need callers, tests, or related functions
   - 0.0-0.4: Low — missing critical context, expand search
3. **REFINE**: Read next most relevant context based on evaluation
4. **LOOP**: Repeat until ≥0.8 relevance or 3 cycles exhausted

### Priority order for context expansion
1. Enclosing function/method body
2. Callers of changed symbols
3. Tests for changed symbols
4. Related type definitions / interfaces
5. Import chains and dependencies

### Guard rails
- Max 3 refinement cycles
- Max 3 additional reads per cycle
- Stop at "good enough" (≥0.8) — don't chase perfection
- Total subagent context: ≤2000 tokens of code
