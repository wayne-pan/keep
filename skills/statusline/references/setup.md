# Statusline Setup Detail

Detailed steps for `/keep:statusline:setup`. Run once, persists across sessions.

## Step 1: Verify Python

```bash
python3 --version
```

If not found, tell user to install Python 3.8+ and re-run `/keep:statusline:setup`.

## Step 2: Deploy Files

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

## Step 3: Test

```bash
# Use the script at shared location (works for all agents)
echo '{"model":{"display_name":"test"},"context_window":{"used_percentage":50},"cwd":"/tmp"}' | python3 -u ~/.local/share/keep/scripts/statusline.py
```

If no output or errors, debug before proceeding. Common issues:
- Missing python3: install Python 3.8+
- Permission denied: `chmod +x ~/.local/share/keep/scripts/statusline.py`

## Step 4: Configure Agent

### Claude Code (native statusLine supported)

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

### OpenCode (no native statusLine)

OpenCode does not have a native statusLine feature yet (tracked as [issue #8619](https://github.com/anomalyco/opencode/issues/8619)).

Inform the user:
- "OpenCode doesn't support custom statusline yet (tracking: github.com/anomalyco/opencode/issues/8619)."
- "The statusline script is installed at ~/.local/share/keep/scripts/statusline.py and will work once OpenCode adds statusLine support."
- "You can test it manually: `echo '{\"model\":{\"display_name\":\"test\"},\"context_window\":{\"used_percentage\":50},\"cwd\":\"/tmp\"}' | python3 -u ~/.local/share/keep/scripts/statusline.py`"

### Codex (no native statusLine)

Same as OpenCode — inform user that Codex doesn't support custom statusline. The script is deployed to `~/.local/share/keep/scripts/` and ready for future use.

### Unknown Agent

Deploy to shared location (`~/.local/share/keep/scripts/`) and inform user that statusline support depends on their agent. They can test the script manually.

## Step 5: Verify

**For Claude Code**, use AskUserQuestion:
- Question: "Statusline configured! Restart Claude Code (quit and re-open). Is it showing?"
- Options: "Yes, working" / "No, not showing"

**If not working**, debug:
1. Check settings.json has correct `statusLine.command`
2. Check symlinks: `ls -la ~/.claude/scripts/statusline.py` → should point to `~/.local/share/keep/scripts/statusline.py`
3. Test command manually: `echo '{}' | python3 -u ~/.local/share/keep/scripts/statusline.py`
4. Check for Python stdout buffering: ensure `-u` flag is in the command

**For OpenCode / Codex**, confirm the script is deployed and show the manual test command.
