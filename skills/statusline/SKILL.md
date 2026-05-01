---
name: keep:statusline
triggers: ["/keep:statusline", "/keep:statusline:setup", "/keep:statusline:pricing", "/keep:statusline:status", "/keep:statusline:remove"]
description: Native statusline for Claude Code — zero dependencies
allowed-tools: Bash, Read, Edit, Write, AskUserQuestion
user-invocable: true
---

# Native Statusline

Zero-dependency Python statusline replacing claude-hud. Shows model, tokens, cache ratio, cost, tools, and config info.

## Setup: `/keep:statusline:setup`

Configure the native statusline. Run once, persists across sessions.

### Step 1: Verify Python

Check python3 is available:
```bash
python3 --version
```
If not found, tell user to install Python 3.8+ and re-run `/keep:statusline:setup`.

### Step 2: Deploy Files

```bash
mkdir -p ~/.claude/scripts
cp scripts/statusline.py ~/.claude/scripts/statusline.py
cp scripts/pricing.json ~/.claude/scripts/pricing.json
chmod +x ~/.claude/scripts/statusline.py
```

### Step 3: Test

```bash
echo '{"model":{"display_name":"test"},"context_window":{"used_percentage":50},"cwd":"/tmp"}' | python3 -u ~/.claude/scripts/statusline.py
```

If no output or errors, debug before proceeding. Common issues:
- Missing python3: install Python 3.8+
- Permission denied: `chmod +x ~/.claude/scripts/statusline.py`

### Step 4: Update Settings

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

### Step 5: Verify

Use AskUserQuestion:
- Question: "Statusline configured! Restart Claude Code (quit and re-open). Is it showing?"
- Options: "Yes, working" / "No, not showing"

**If not working**, debug:
1. Check settings.json has correct `statusLine.command`
2. Test command manually: `echo '{}' | python3 -u ~/.claude/scripts/statusline.py`
3. Check for Python stdout buffering: ensure `-u` flag is in the command

## Pricing: `/keep:statusline:pricing`

Manage model pricing table. All prices are per 1M tokens (USD).

Config file: `~/.claude/scripts/pricing.json`

### View Current Pricing

```bash
cat ~/.claude/scripts/pricing.json | python3 -c "
import json, sys
data = json.load(sys.stdin)
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

Then update `~/.claude/scripts/pricing.json`:
- Read the existing file
- Add/update the entry in `models`
- Write back with proper formatting

Example entry:
```json
"gpt-4o": { "in": 2.5, "out": 10, "provider": "openai" }
```

### Remove Model

Remove the entry from `models` in `~/.claude/scripts/pricing.json`.

### Update Cache Multipliers

Ask the user for the cache multiplier values. Anthropic standard: write 1.25x, read 0.1x. If the provider doesn't support cache billing, set both to 0.

Update the `_cache` section in `~/.claude/scripts/pricing.json`.

### Find Model Pricing

If the user asks about pricing for a model not in the table:
1. Search the web for "[model name] API pricing per million tokens"
2. Present the findings
3. Ask if they want to add it to the pricing table

## Status: `/keep:statusline:status`

Show current statusline configuration and health.

```bash
# Check if configured
jq '.statusLine' ~/.claude/settings.json 2>/dev/null || echo "Not configured"

# Check if script exists
ls -la ~/.claude/scripts/statusline.py ~/.claude/scripts/pricing.json 2>/dev/null || echo "Files missing"

# Test run
echo '{"model":{"display_name":"test"},"context_window":{"used_percentage":50},"cwd":"/tmp"}' | python3 -u ~/.claude/scripts/statusline.py
```

Report the results to the user.

## Uninstall: `/keep:statusline:remove`

Remove the native statusline configuration.

1. Remove `statusLine` key from `~/.claude/settings.json`
2. Optionally remove `~/.claude/scripts/statusline.py` and `pricing.json`
3. Tell user to restart Claude Code

## Triggers

- `/keep:statusline` or `/keep:statusline:setup` — Configure statusline
- `/keep:statusline:pricing` — View/manage model pricing
- `/keep:statusline:status` — Check statusline health
- `/keep:statusline:remove` — Remove statusline
