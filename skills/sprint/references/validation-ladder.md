# Validation Ladder

Automatic verification after each implementation step. Inspired by GSD-2's validation gates.

## Per-Edit Validation

After EVERY file edit, run the appropriate syntax/validity check:

| File type | Auto-validation command |
|-----------|------------------------|
| `.sh` | `bash -n <file>` (syntax check) |
| `.py` | `python3 -c "import ast; ast.parse(open('<file>').read())"` |
| `.js` | `node --check <file>` |
| `.ts` | `npx tsc --noEmit <file>` (if tsconfig exists) |
| `.json` | `python3 -m json.tool <file> > /dev/null` |
| `.yaml/.yml` | `python3 -c "import yaml; yaml.safe_load(open('<file>'))"` |
| `.md` | No auto-validation (visual check only) |
| Any | `git diff --stat` to verify change scope is as planned |

## Per-Module Validation

After completing a module (related set of file changes):

1. **Static analysis**: Run linter for the language
   - Python: `ruff check` or `flake8`
   - Shell: `shellcheck`
   - JS/TS: `eslint`
2. **Unit tests**: Run tests for the changed module
   - If tests fail → auto-fix (1 retry with different approach)
   - If still fails → escalate to user

## Per-Sprint Validation

After ALL modules are implemented (before Review phase):

1. **Full test suite**: `pytest` / `npm test` / `cargo test` / etc.
2. **Integration tests**: If they exist, run them
3. **Build check**: Verify project builds cleanly
4. **Lint full project**: Not just changed files

## Auto-Fix Protocol

When validation fails:
1. Read the error output carefully
2. Fix the root cause, not the symptom
3. Re-run validation
4. If same error persists after 1 retry → different approach needed
5. After 2 retries on same error → STOP, write to `.sprint/STUCK.md`, escalate

## Validation in Subagents

When using Agent subagents for implementation:
- Include validation command in the subagent prompt
- Example: "After editing file.sh, run `bash -n file.sh` to verify syntax"
- Subagent should report validation results in its output
