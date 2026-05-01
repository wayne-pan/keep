# Context Engineering Reference

Deep-dive on context management for the sprint workflow.

## Context Budget

Context is working memory, not storage — budget it like RAM.

- Before full-reading a file >100 lines: justify why `smart_outline` or `offset/limit` won't suffice
- After each subagent return: discard raw output, keep only conclusions (under 200 words)
- If approaching context limits: proactively compact before degradation hits
- Memory entry files must stay under 200 lines; split to topic files when exceeding
- Session state priority: Current State > Errors & Corrections > Plan > Worklog
- After compact: verify plan, active skills, and error context survived
- **Tool call budget**: 30 calls/task default, 50 for complex (3+ files), ≤10 for trivial

## Context Hygiene Rules

- **Research phase output** must be compressed — no raw tool output in research notes
- **Plan phase** must include specific file paths and line numbers — no vague directives
- **Implement phase** must discard subagent raw output immediately after use
- If context >50% full at any phase boundary: warn user, suggest fresh window
- Each phase boundary is a compression checkpoint — summarize before proceeding

## Task Management

1. **Plan First**: Write plan to `tasks/todo.md` with checkable items
2. **Verify Plan**: Check in before starting implementation
3. **Track Progress**: Mark items complete as you go
4. **Explain Changes**: High-level summary at each step
5. **Document Results**: Add review section to `tasks/todo.md`
6. **Capture Lessons**: Update `tasks/lessons.md` after corrections

## Context Trimming (Review-Optimized)

When reading code for review or analysis, only send relevant slices — not entire files:

- **Changed region**: ±10 lines around diff hunks (`git diff -U10`)
- **Enclosing function**: The function containing the change, not the whole file
- **Caller signatures**: Only function signatures of blast radius callers, not their bodies
- **Skip entirely**: Import blocks, docstrings, comments, test fixtures (unless in diff)

This reduces review context from potentially thousands of tokens to a few hundred per finding.
