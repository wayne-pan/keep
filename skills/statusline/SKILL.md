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

Statusline setup varies by agent. Detect which agent is running:

```bash
if [ "${CLAUDECODE:-}" = "1" ]; then echo "claude-code"
elif [ "${OPENCODE:-}" != "" ] || command -v opencode &>/dev/null; then echo "opencode"
elif [ "${CODEX_HOME:-}" != "" ] || command -v codex &>/dev/null; then echo "codex"
else echo "unknown"
fi
```

**Agent statusline support:**

| Agent | Native statusLine | Config path |
|-------|-------------------|-------------|
| Claude Code | Yes | `~/.claude/settings.json` |
| OpenCode | No (issue #8619) | N/A |
| Codex | No | N/A |

## Setup: `/keep:statusline:setup`

Configure the native statusline. Run once, persists across sessions.

### Step 0: Detect Agent

Run the detection command above. Branch based on result.

### Step 1: Verify Python

Check python3 is available:
```bash
python3 --version
```
If not found, tell user to install Python 3.8+ and re-run `/keep:statusline:setup`.

### Step 2: Deploy Files

**For Claude Code** (deploy to agent-specific + shared location):
```bash
# Agent-specific (for statusLine command)
mkdir -p ~/.claude/scripts
cp scripts/statusline.py ~/.claude/scripts/statusline.py
cp scripts/pricing.json ~/.claude/scripts/pricing.json
chmod +x ~/.claude/scripts/statusline.py

# Shared (for other agents)
mkdir -p ~/.local/share/keep/scripts
cp scripts/statusline.py ~/.local/share/keep/scripts/statusline.py
cp scripts/pricing.json ~/.local/share/keep/scripts/pricing.json
chmod +x ~/.local/share/keep/scripts/statusline.py
```

**For OpenCode / Codex / Unknown** (deploy to shared location only):
```bash
mkdir -p ~/.local/share/keep/scripts
cp scripts/statusline.py ~/.local/share/keep/scripts/statusline.py
cp scripts/pricing.json ~/.local/share/keep/scripts/pricing.json
chmod +x ~/.local/share/keep/scripts/statusline.py
```

### Step 3: Test

**Claude Code:**
```bash
echo '{"model":{"display_name":"test"},"context_window":{"used_percentage":50},"cwd":"/tmp"}' | python3 -u ~/.claude/scripts/statusline.py
```

**OpenCode / Codex / Unknown:**
```bash
echo '{"model":{"display_name":"test"},"context_window":{"used_percentage":50},"cwd":"/tmp"}' | python3 -u ~/.local/share/keep/scripts/statusline.py
```

If no output or errors, debug before proceeding. Common issues:
- Missing python3: install Python 3.8+
- Permission denied: `chmod +x` the script

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
2. Test command manually: `echo '{}' | python3 -u ~/.claude/scripts/statusline.py`
3. Check for Python stdout buffering: ensure `-u` flag is in the command

**For OpenCode / Codex**, confirm the script is deployed and show the manual test command.

## Pricing: `/keep:statusline:pricing`

Manage model pricing table. All prices are per 1M tokens (USD).

Config file location (use the first that exists):
1. `~/.claude/scripts/pricing.json` (Claude Code deployment)
2. `~/.local/share/keep/scripts/pricing.json` (shared deployment)

### View Current Pricing

```bash
PRICING="${HOME}/.claude/scripts/pricing.json"
[ -f "$PRICING" ] || PRICING="${HOME}/.local/share/keep/scripts/pricing.json"
cat "$PRICING" | python3 -c "
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

Then update the pricing file (resolve path as above):
- Read the existing file
- Add/update the entry in `models`
- Write back with proper formatting
- If both locations exist, update both

Example entry:
```json
"gpt-4o": { "in": 2.5, "out": 10, "provider": "openai" }
```

### Remove Model

Remove the entry from `models` in the pricing file. If both locations exist, update both.

### Update Cache Multipliers

Ask the user for the cache multiplier values. Anthropic standard: write 1.25x, read 0.1x. If the provider doesn't support cache billing, set both to 0.

Update the `_cache` section in the pricing file.

### Find Model Pricing

If the user asks about pricing for a model not in the table:
1. Search the web for "[model name] API pricing per million tokens"
2. Present the findings
3. Ask if they want to add it to the pricing table

## Status: `/keep:statusline:status`

Show current statusline configuration and health.

```bash
# Detect agent
AGENT=$(if [ "${CLAUDECODE:-}" = "1" ]; then echo "claude-code"
  elif [ "${OPENCODE:-}" != "" ] || command -v opencode &>/dev/null; then echo "opencode"
  elif [ "${CODEX_HOME:-}" != "" ] || command -v codex &>/dev/null; then echo "codex"
  else echo "unknown"; fi)
echo "Detected agent: $AGENT"

# Check agent-specific config
if [ "$AGENT" = "claude-code" ]; then
  jq '.statusLine' ~/.claude/settings.json 2>/dev/null || echo "Not configured in settings.json"
  ls -la ~/.claude/scripts/statusline.py ~/.claude/scripts/pricing.json 2>/dev/null || echo "Claude Code files missing"
fi

# Check shared deployment
ls -la ~/.local/share/keep/scripts/statusline.py ~/.local/share/keep/scripts/pricing.json 2>/dev/null || echo "Shared files missing"

# Test run
SCRIPT="${HOME}/.claude/scripts/statusline.py"
[ -f "$SCRIPT" ] || SCRIPT="${HOME}/.local/share/keep/scripts/statusline.py"
echo '{"model":{"display_name":"test"},"context_window":{"used_percentage":50},"cwd":"/tmp"}' | python3 -u "$SCRIPT"
```

Report the results to the user.

## Uninstall: `/keep:statusline:remove`

Remove the native statusline configuration.

1. If Claude Code: remove `statusLine` key from `~/.claude/settings.json`
2. Optionally remove agent-specific files: `~/.claude/scripts/statusline.py` and `pricing.json`
3. Optionally remove shared files: `~/.local/share/keep/scripts/statusline.py` and `pricing.json`
4. Tell user to restart their agent

## Triggers

- `/keep:statusline` or `/keep:statusline:setup` — Configure statusline
- `/keep:statusline:pricing` — View/manage model pricing
- `/keep:statusline:status` — Check statusline health
- `/keep:statusline:remove` — Remove statusline
