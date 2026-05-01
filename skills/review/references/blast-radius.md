# Blast Radius Analysis

Trace the impact of code changes beyond the immediate diff. Inspired by code-review-graph's BFS impact analysis.

## Concept

When code changes, the impact extends beyond the changed file. A function signature change affects all callers. A new import affects the dependency graph. Blast radius analysis traces these chains.

## Manual BFS Method (no infrastructure required)

### Step 1: Identify Changed Symbols
From the git diff, extract changed function/class/method names:
```bash
git diff HEAD~1 --unified=0 | grep -E "^[-+].*(function |def |class |^[a-zA-Z_]+\(\))" | sort -u
```

### Step 2: Forward Trace (who depends on this?)
For each changed symbol, find all callers:
```bash
# Shell functions
grep -rn "function_name" --include="*.sh" .
# Python
grep -rn "function_name\|ClassName\|import.*module" --include="*.py" .
# JavaScript
grep -rn "functionName\|className\|from.*module" --include="*.js" --include="*.ts" .
```

### Step 3: Backward Trace (what does this depend on?)
For each changed symbol, find its dependencies:
```bash
# What does this file import/source?
grep -E "^(source|import|require|from)" changed_file.sh
```

### Step 4: Test Coverage Check
For each changed symbol, find related tests:
```bash
grep -rn "function_name\|describe.*functionName\|def test.*function" --include="*test*" .
```

### Step 5: Report Blast Radius
```
## Blast Radius
Changed: func_a (file.sh:15)
├── Callers: func_b (file.sh:42), func_c (other.sh:10)
├── Tests: test_func_a (test_file.sh:5)
└── Impact: MEDIUM — 2 callers, 1 test, no external consumers
```

## 2-Hop Default

Stop at 2 hops (callers of callers) by default. For critical changes (API boundary, security-sensitive code), extend to 3 hops.

## Integration with /keep:review

After gathering git diff changes (Step 1), run blast radius analysis before spawning review subagents. Include the blast radius in the subagent prompts so they can focus on the actual impact zone.

## Incremental Code Map (lightweight cache)

For projects where blast radius is run frequently, maintain `.sprint/CODE_MAP.md`:

```markdown
# Code Map (auto-generated, incremental)

## hooks/safety-guard.sh
- `check_command()` :15 — validates tool input against dangerous patterns
- `main()` :30 — reads stdin, calls check_command, exits 0/1
- Callers: settings.json (PreToolUse hook)
- Deps: none

## scripts/install.sh
- `install_mx()` :45 — copies skills, rules, hooks to ~/.claude/
- `configure()` :80 — writes settings.json with hook registration
- Callers: main()
- Deps: ~/.claude/ directory structure
```

Update incrementally: only re-scan files that appear in `git diff --name-only HEAD~1`.
