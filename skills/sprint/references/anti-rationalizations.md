# Common Rationalizations

Rationalizations that lead to bugs and how to counter them.

| Rationalization | Reality |
|---|---|
| "The existing tests cover it" | Run them. If you haven't seen them pass, they don't count. |
| "I'll add tests later" | You won't. Write tests first or alongside implementation. |
| "I'll optimize later" | You won't. Ship the simplest correct solution now. |
| "This plan is good enough" | If it doesn't have file paths and line numbers, it's not a plan — it's a wish. |
| "The docs describe the architecture" | Docs lie. Code is truth. Read the actual code before planning. |
| "This is a simple change" | Simple changes cause the most bugs because you let your guard down. Run the full protocol. |
| "I'll skip Research, I know the codebase" | You don't. Code changes faster than memory. Fresh snapshot every time. |
| "I can do this without a plan" | If it's <5 lines in 1 file, sure. Otherwise you're gambling. |
| "More context is always better" | Performance degrades with too many instructions. Compress ruthlessly. |
| "The user can review the code" | Human attention doesn't scale to AI output volume. Review plans, not code. |

## How to Use This Table

When you catch yourself thinking any of the left-column thoughts:
1. Stop and acknowledge the rationalization
2. Read the reality check on the right
3. Follow the protocol anyway — the process exists because these rationalizations are seductive
