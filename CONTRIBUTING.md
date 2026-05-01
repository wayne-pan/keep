# Contributing to keep

Thank you for your interest in contributing! This guide covers the basics.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/your-username/keep.git`
3. Install: `bash scripts/install.sh`
4. Create a branch: `git checkout -b my-feature`

## Development

### Project Structure

```
mem/       → Memory MCP server (Python, FastMCP + SQLite)
hooks/     → Claude Code hooks (bash, PreToolUse/PostToolUse)
skills/    → Skill workflows (SKILL.md + references/)
scripts/   → Installer, model manager, benchmarks (bash + python)
rules/     → Behavioral rules (markdown)
```

### Making Changes

- **Hooks** (`hooks/`): Bash scripts using stdin/stdout JSON protocol. Always add to `scripts/install.sh` deployment list.
- **Skills** (`skills/`): Create `skills/<name>/SKILL.md` with YAML frontmatter. Optional `references/` for deep docs.
- **Memory server** (`mem/`): Python with FastMCP. Only external dependency is `mcp`.
- **Rules** (`rules/`): Markdown files deployed to `~/.claude/rules/`.

### Validation

After changes, run:

```bash
# Syntax check all bash scripts
for f in hooks/*.sh scripts/*.sh; do bash -n "$f" && echo "OK: $f"; done

# Syntax check Python
python3 -m py_compile mem/server.py

# Quick benchmark (4 tests)
bash scripts/benchmark.sh --quick
```

### Commit Style

- Use conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`
- Keep commits atomic — one logical change per commit
- No TODO/FIXME in committed code (enforced by `no-todo-commit.sh` hook)

## Pull Requests

1. Ensure all validation passes
2. Update documentation if you changed behavior
3. Add your change to the PR description with context on why

## Reporting Issues

- Bug reports: include OS, Claude Code version, and reproduction steps
- Feature requests: describe the use case, not just the solution

## Code of Conduct

Be respectful, constructive, and inclusive. We're all here to make AI coding assistants better.
