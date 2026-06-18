---
name: keep:statusline
version: "1.2"
triggers: ["/keep:statusline", "/keep:statusline:setup", "/keep:statusline:pricing", "/keep:statusline:status", "/keep:statusline:remove"]
description: >
  Native statusline for AI coding agents — zero dependencies. TRIGGER when: user says
  /keep:statusline or any sub-mode (setup/pricing/status/remove), or asks to configure
  the statusline. Do NOT trigger for: general UI tweaks, agent theme changes.
allowed-tools: Bash, Read, Edit, Write, AskUserQuestion
resources: ['settings-json', 'git']
user-invocable: true
---

# Native Statusline

Zero-dependency Python statusline replacing claude-hud. Shows model, tokens, cache ratio, cost, tools, and config info.

## Agent Detection

Statusline setup varies by agent. Use this detection snippet everywhere:

```bash
detect_agent() {
  local count=0 agent=""
  if [ "${CLAUDECODE:-}" = "1" ]; then agent="claude-code"; count=$((count+1)); fi
  if [ "${OPENCODE:-}" != "" ]; then agent="opencode"; count=$((count+1)); fi
  if [ "${CODEX_HOME:-}" != "" ]; then agent="codex"; count=$((count+1)); fi
  if [ "$count" = "0" ]; then
    if command -v claude &>/dev/null; then agent="claude-code"
    elif command -v opencode &>/dev/null; then agent="opencode"
    elif command -v codex &>/dev/null; then agent="codex"
    else agent="unknown"
    fi
  elif [ "$count" -gt 1 ]; then
    echo "WARNING: multiple agent env vars set ($count), using: $agent" >&2
  fi
  echo "$agent"
}
```

**Agent statusline support:**

| Agent | Native statusLine | Script location |
|-------|-------------------|-----------------|
| Claude Code | Yes | `~/.claude/scripts/` (symlinks to shared) |
| OpenCode | No (issue #8619) | `~/.local/share/keep/scripts/` |
| Codex | No | `~/.local/share/keep/scripts/` |

**Canonical data location**: `~/.local/share/keep/scripts/pricing.json` — single source of truth. Claude Code's `~/.claude/scripts/pricing.json` is a symlink to this file.

## Triggers

- `/keep:statusline` or `/keep:statusline:setup` — Configure statusline
- `/keep:statusline:pricing` — View/manage model pricing
- `/keep:statusline:status` — Check statusline health
- `/keep:statusline:remove` — Remove statusline

## `/keep:statusline:setup`

Run `detect_agent` first, branch based on result. Then 5 steps:

1. **Verify Python** — `python3 --version` (3.8+ required)
2. **Deploy files** — copy to `~/.local/share/keep/scripts/`; for Claude Code also symlink to `~/.claude/scripts/`
3. **Test** — pipe sample JSON through `statusline.py`, expect rendered output
4. **Configure agent** — Claude Code: set `statusLine` in `~/.claude/settings.json`; OpenCode/Codex: inform user (no native support yet)
5. **Verify** — for Claude Code, ask user via AskUserQuestion whether it shows after restart

Full commands and per-agent branching: `references/setup.md`.

## `/keep:statusline:pricing`

Manage model pricing table. All prices per 1M tokens (USD). Canonical: `~/.local/share/keep/scripts/pricing.json`.

Operations: view current pricing, add/update model, remove model, update cache multipliers, find pricing for un-listed model (web search).

Full commands and Python viewer: `references/pricing.md`.

## `/keep:statusline:status`

Show current statusline configuration and health.

```bash
# Detect agent (run detect_agent from Agent Detection section)
AGENT=$(detect_agent)
echo "Detected agent: $AGENT"

# Check shared deployment (canonical location)
if [ -f ~/.local/share/keep/scripts/statusline.py ]; then
  echo "Shared statusline: OK"
else
  echo "Shared statusline: MISSING"
fi

# Check agent-specific config
if [ "$AGENT" = "claude-code" ]; then
  # Check symlinks
  if [ -L ~/.claude/scripts/statusline.py ]; then
    echo "Claude Code symlink: OK ($(readlink ~/.claude/scripts/statusline.py))"
  else
    echo "Claude Code symlink: MISSING or not a symlink"
  fi
  # Check statusLine in settings (use python if jq unavailable)
  if command -v jq &>/dev/null; then
    jq '.statusLine' ~/.claude/settings.json 2>/dev/null || echo "Not configured in settings.json"
  else
    python3 -c "import json; d=json.load(open('$HOME/.claude/settings.json')); print(json.dumps(d.get('statusLine','Not configured')))" 2>/dev/null || echo "settings.json not found"
  fi
fi

# Test run from canonical location
SCRIPT="${HOME}/.local/share/keep/scripts/statusline.py"
if [ -f "$SCRIPT" ]; then
  echo '{"model":{"display_name":"test"},"context_window":{"used_percentage":50},"cwd":"/tmp"}' | python3 -u "$SCRIPT"
else
  echo "Cannot test: script not found at $SCRIPT"
fi
```

Report the results to the user.

## `/keep:statusline:remove`

Remove the native statusline configuration.

1. If Claude Code: remove `statusLine` key from `~/.claude/settings.json`
2. Remove symlinks: `~/.claude/scripts/statusline.py` and `~/.claude/scripts/pricing.json`
3. Optionally remove canonical files: `~/.local/share/keep/scripts/statusline.py` and `pricing.json`
4. Tell user to restart their agent

## References

- `references/setup.md` — full 5-step setup with per-agent branching and debug
- `references/pricing.md` — pricing view command, add/update/remove model, cache multipliers
