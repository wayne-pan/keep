---
name: keep:statusline
triggers: ["/keep:statusline", "/keep:statusline:setup", "/keep:statusline:pricing", "/keep:statusline:status", "/keep:statusline:remove"]
description: Native statusline for AI coding agents — zero dependencies
allowed-tools: Bash, Read, Edit, Write, AskUserQuestion
user-invocable: true
---

# Native Statusline

Zero-dependency Python statusline replacing claude-hud. Shows model, tokens, cache ratio, cost, tools, and config info.

## Agent Detection

Statusline setup varies by agent. Use this detection snippet everywhere (defined once, reference from other sections):

```bash
detect_agent() {
  local count=0 agent=""
  if [ "${CLAUDECODE:-}" = "1" ]; then agent="claude-code"; count=$((count+1)); fi
  if [ "${OPENCODE:-}" != "" ]; then agent="opencode"; count=$((count+1)); fi
  if [ "${CODEX_HOME:-}" != "" ]; then agent="codex"; count=$((count+1)); fi
  # Fallback: only if no env var matched
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

## Setup: `/keep:statusline:setup`

Configure the native statusline. Run once, persists across sessions.

### Step 0: Detect Agent

Run `detect_agent` from the Agent Detection section above. Branch based on result.

### Step 1: Verify Python

Check python3 is available:
```bash
python3 --version
```
If not found, tell user to install Python 3.8+ and re-run `/keep:statusline:setup`.

### Step 2: Deploy Files

Always deploy to the shared canonical location. For Claude Code, also create symlinks from `~/.claude/scripts/`.

**All agents:**
```bash
# Shared canonical location
mkdir -p ~/.local/share/keep/scripts
cp scripts/statusline.py ~/.local/share/keep/scripts/statusline.py
cp scripts/pricing.json ~/.local/share/keep/scripts/pricing.json
chmod +x ~/.local/share/keep/scripts/statusline.py
```

**Additionally for Claude Code** (symlink so statusLine command finds the script):
```bash
mkdir -p ~/.claude/scripts
ln -sf ~/.local/share/keep/scripts/statusline.py ~/.claude/scripts/statusline.py
ln -sf ~/.local/share/keep/scripts/pricing.json ~/.claude/scripts/pricing.json
```

### Step 3: Test

```bash
# Use the script at shared location (works for all agents)
echo '{"model":{"display_name":"test"},"context_window":{"used_percentage":50},"cwd":"/tmp"}' | python3 -u ~/.local/share/keep/scripts/statusline.py
```

If no output or errors, debug before proceeding. Common issues:
- Missing python3: install Python 3.8+
- Permission denied: `chmod +x ~/.local/share/keep/scripts/statusline.py`

### Step 4: Configure Agent

#### Claude Code (native statusLine supported)

Read `~/.claude/settings.json`. If it doesn't exist, create it.

Set `statusLine` and remove old plugin references:
```json
{
  "statusLine": {
    "type": "command",
    "command": "bash -c 'python3 -u ~/.claude/scripts/statusline.py'"
  }
}
```

Also remove these keys if present (old claude-hud):
- `enabledPlugins`
- `extraKnownMarketplaces`

Use the `update-config` skill or Edit tool to update settings.json. Preserve all other settings.

#### OpenCode (no native statusLine)

OpenCode does not have a native statusLine feature yet (tracked as [issue #8619](https://github.com/anomalyco/opencode/issues/8619)).

Inform the user:
- "OpenCode doesn't support custom statusline yet (tracking: github.com/anomalyco/opencode/issues/8619)."
- "The statusline script is installed at ~/.local/share/keep/scripts/statusline.py and will work once OpenCode adds statusLine support."
- "You can test it manually: `echo '{\"model\":{\"display_name\":\"test\"},\"context_window\":{\"used_percentage\":50},\"cwd\":\"/tmp\"}' | python3 -u ~/.local/share/keep/scripts/statusline.py`"

#### Codex (no native statusLine)

Same as OpenCode — inform user that Codex doesn't support custom statusline. The script is deployed to `~/.local/share/keep/scripts/` and ready for future use.

#### Unknown Agent

Deploy to shared location (`~/.local/share/keep/scripts/`) and inform user that statusline support depends on their agent. They can test the script manually.

### Step 5: Verify

**For Claude Code**, use AskUserQuestion:
- Question: "Statusline configured! Restart Claude Code (quit and re-open). Is it showing?"
- Options: "Yes, working" / "No, not showing"

**If not working**, debug:
1. Check settings.json has correct `statusLine.command`
2. Check symlinks: `ls -la ~/.claude/scripts/statusline.py` → should point to `~/.local/share/keep/scripts/statusline.py`
3. Test command manually: `echo '{}' | python3 -u ~/.local/share/keep/scripts/statusline.py`
4. Check for Python stdout buffering: ensure `-u` flag is in the command

**For OpenCode / Codex**, confirm the script is deployed and show the manual test command.

## Pricing: `/keep:statusline:pricing`

Manage model pricing table. All prices are per 1M tokens (USD).

**Canonical config file**: `~/.local/share/keep/scripts/pricing.json`
(Symlinked from `~/.claude/scripts/pricing.json` for Claude Code — single source of truth, no drift.)

### View Current Pricing

```bash
PRICING="${HOME}/.local/share/keep/scripts/pricing.json"
if [ ! -f "$PRICING" ]; then
  echo "Error: pricing file not found at $PRICING"; exit 1
fi
python3 -c "
import json, sys
data = json.load(open('$PRICING'))
print('Model pricing (per 1M tokens):')
print(f'{'Model':<12} {'Input':>8} {'Output':>8}  Provider')
print('-' * 44)
for k, v in sorted(data.get('models', {}).items()):
    if k.startswith('_'): continue
    print(f'{k:<12} \${v[\"in\"]:>6.2f}  \${v[\"out\"]:>6.2f}  {v.get(\"provider\", \"?\")}')
c = data.get('_cache', {})
print(f'\nCache multipliers: write {c.get(\"write_mult\", 1.25)}x, read {c.get(\"read_mult\", 0.1)}x')
r = data.get('_reference', {})
print(f'Reference model: {r.get(\"model\", \"sonnet\")}')
"
```

### Add / Update Model

Ask the user for model details:
- Model name (substring to match, e.g. "gpt-4o", "/keep:glm-5")
- Input price (per 1M tokens)
- Output price (per 1M tokens)
- Provider name (optional)

Then update the canonical pricing file:
1. Read `~/.local/share/keep/scripts/pricing.json`
2. Add/update the entry in `models`
3. Write back with proper formatting

Example entry:
```json
"gpt-4o": { "in": 2.5, "out": 10, "provider": "openai" }
```

### Remove Model

Remove the entry from `models` in `~/.local/share/keep/scripts/pricing.json`.

### Update Cache Multipliers

Ask the user for the cache multiplier values. Anthropic standard: write 1.25x, read 0.1x. If the provider doesn't support cache billing, set both to 0.

Update the `_cache` section in `~/.local/share/keep/scripts/pricing.json`.

### Find Model Pricing

If the user asks about pricing for a model not in the table:
1. Search the web for "[model name] API pricing per million tokens"
2. Present the findings
3. Ask if they want to add it to the pricing table

## Status: `/keep:statusline:status`

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

## Uninstall: `/keep:statusline:remove`

Remove the native statusline configuration.

1. If Claude Code: remove `statusLine` key from `~/.claude/settings.json`
2. Remove symlinks: `~/.claude/scripts/statusline.py` and `~/.claude/scripts/pricing.json`
3. Optionally remove canonical files: `~/.local/share/keep/scripts/statusline.py` and `pricing.json`
4. Tell user to restart their agent

## Triggers

- `/keep:statusline` or `/keep:statusline:setup` — Configure statusline
- `/keep:statusline:pricing` — View/manage model pricing
- `/keep:statusline:status` — Check statusline health
- `/keep:statusline:remove` — Remove statusline
