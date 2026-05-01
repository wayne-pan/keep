# `/keep:review ideate` Protocol

Proactive codebase scan for improvement opportunities (not diff-based).

## Process

1. Scan codebase for signals:
   - **Complexity hotspots**: high nesting depth, long functions, deep coupling
   - **Stale patterns**: TODO/FIXME comments, deprecated API usage, inconsistent naming
   - **Missing coverage**: code paths with no corresponding tests
   - **Security gaps**: hardcoded secrets, weak validation, missing auth checks
   - **Dead code**: unused imports, unreachable exports, commented-out code blocks

2. Rank opportunities by impact × effort:
   - **high**: Security fixes, removing dead code, tests for critical paths
   - **medium**: Refactoring opportunities, missing tests for non-critical paths
   - **low**: Style improvements, minor TODO cleanup

3. Present top 10 ranked suggestions with rationale

4. User picks which to pursue (or skip all)

## Keyword Steering

Optionally steer with a keyword: `/keep:review ideate auth` focuses on security-related improvements.

## When to Use

- At sprint Reflect phase as a proactive quality gate
- When onboarding to a new codebase
- Before a major refactoring effort
- Periodically as maintenance hygiene
