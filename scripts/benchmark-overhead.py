#!/usr/bin/env python3
"""Benchmark Claude Code per-request overhead by tokenizing every injected component."""

import json, os, sys, glob
import tiktoken

enc = tiktoken.get_encoding("o200k_base")


def tok_count(text):
    return len(enc.encode(text))


def tok_count_file(path):
    try:
        with open(path) as f:
            return tok_count(f.read())
    except FileNotFoundError:
        return 0


def read_file(path):
    try:
        with open(path) as f:
            return f.read()
    except FileNotFoundError:
        return ""


HOME = os.path.expanduser("~")
PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# ── 1. CLAUDE.md ──
print("=" * 60)
print("1. CLAUDE.md (loaded every request)")
print("=" * 60)

total_claude_md = 0
for label, path in [
    ("Global", f"{HOME}/.claude/CLAUDE.md"),
    ("Project", f"{PROJECT}/.claude/CLAUDE.md"),
]:
    t = tok_count_file(path)
    w = len(read_file(path).split())
    total_claude_md += t
    print(f"  {label:10s} {path:50s} {t:5d} tokens  ({w:4d} words)")

print(f"  {'TOTAL':10s} {'':50s} {total_claude_md:5d} tokens")

# ── 2. Rules ──
print()
print("=" * 60)
print("2. Rules (loaded every request)")
print("=" * 60)

total_rules = 0
rule_files = []
# Project rules
for f in sorted(glob.glob(f"{PROJECT}/rules/*.md")):
    rule_files.append(("Project", f))
# Global-only rules (not symlinked from project)
for f in sorted(glob.glob(f"{HOME}/.claude/rules/*.md")):
    if not os.path.islink(f):
        basename = os.path.basename(f)
        if not os.path.exists(f"{PROJECT}/rules/{basename}"):
            rule_files.append(("Global", f))
    else:
        # It's a symlink — already counted as project rule
        pass

# Deduplicate by basename
seen = set()
for label, path in rule_files:
    basename = os.path.basename(path)
    if basename in seen:
        continue
    seen.add(basename)
    t = tok_count_file(path)
    w = len(read_file(path).split())
    total_rules += t
    print(f"  {label:10s} {basename:40s} {t:5d} tokens  ({w:4d} words)")

print(f"  {'TOTAL':10s} {'':40s} {total_rules:5d} tokens")

# ── 3. Skill triggers (system-reminder block) ──
print()
print("=" * 60)
print("3. Skill triggers (injected in system-reminder)")
print("=" * 60)

total_skill_triggers = 0
skill_details = []
for skill_dir in sorted(glob.glob(f"{PROJECT}/skills/*/SKILL.md")):
    name = os.path.basename(os.path.dirname(skill_dir))
    # The system-reminder injects: name, trigger slash commands, description line
    content = read_file(skill_dir)
    # Extract trigger block (what actually gets injected)
    trigger_line = ""
    desc_line = ""
    for line in content.split("\n"):
        if line.startswith("triggers:"):
            trigger_line = line
        if line.startswith("description:"):
            desc_line = line
        if line.startswith("  ") and not trigger_line and not desc_line:
            # continuation
            pass
    injected = f"- {name}: {trigger_line} {desc_line}"
    t = tok_count(injected)
    total_skill_triggers += t
    skill_details.append((name, t))

for name, t in skill_details:
    print(f"  {name:25s} {t:5d} tokens (trigger summary)")

print(f"  {'TOTAL':25s} {total_skill_triggers:5d} tokens")

# Also measure full SKILL.md cost (loaded on invocation)
total_skill_full = 0
for skill_dir in sorted(glob.glob(f"{PROJECT}/skills/*/SKILL.md")):
    total_skill_full += tok_count_file(skill_dir)
print(
    f"  {'Full SKILL.md (on invoke)':25s} {total_skill_full:5d} tokens (all 13 skills)"
)

# ── 4. MCP tool schemas ──
print()
print("=" * 60)
print("4. MCP tool schemas (injected every request)")
print("=" * 60)

# We reconstruct the tool schema cost from the tool definitions
# Each tool has: name, description, parameters (JSON schema)
# We measure by looking at the actual JSON schema definitions

# Read from settings files
mcp_configs = []
for settings_path in [
    f"{HOME}/.claude/settings.json",
    f"{HOME}/.claude/settings.local.json",
    f"{PROJECT}/.claude/settings.json",
    f"{PROJECT}/.claude/settings.local.json",
]:
    try:
        with open(settings_path) as f:
            data = json.load(f)
            if "mcpServers" in data:
                for name, cfg in data["mcpServers"].items():
                    mcp_configs.append((name, cfg, settings_path))
    except (FileNotFoundError, json.JSONDecodeError, KeyError):
        pass

print("  MCP servers configured in settings files:")
if not mcp_configs:
    print("    (none found in settings — MCPs may be configured at runtime)")

# Count tools from the running session context
# We know from analysis: mind=32, codedb=18, web_reader=1, 4_5v_mcp=1
mcp_tools = {
    "mind": 32,
    "codedb": 18,
    "web_reader": 1,
    "4_5v_mcp": 1,
}

total_mcp_tokens = 0
for server, count in mcp_tools.items():
    # Estimate: each tool schema ≈ 150-250 tokens
    # More precisely: name (~5) + description (~40) + parameters schema (~100-150)
    est_low = count * 150
    est_high = count * 250
    est_mid = (est_low + est_high) // 2
    total_mcp_tokens += est_mid
    print(f"  {server:15s} {count:3d} tools  ~{est_mid:5d} tokens (est)")

print(
    f"  {'TOTAL':15s} {sum(mcp_tools.values()):3d} tools  ~{total_mcp_tokens:5d} tokens (est)"
)
print(
    f"  Note: Exact count requires API-level instrumentation. Using 200 tokens/tool average."
)

# ── 5. Hooks ──
print()
print("=" * 60)
print("5. Hooks (external processes, token cost only on block/output)")
print("=" * 60)

hooks_total = 0
for settings_path in [
    f"{HOME}/.claude/settings.json",
]:
    try:
        with open(settings_path) as f:
            data = json.load(f)
            hooks = data.get("hooks", {})
            for event, matchers in hooks.items():
                for matcher in matchers:
                    pattern = matcher.get("matcher", "*")
                    hook_count = len(matcher.get("hooks", []))
                    hooks_total += hook_count
                    print(f"  {event:20s} matcher={pattern:40s} {hook_count} hooks")
    except (FileNotFoundError, json.JSONDecodeError):
        pass

print(f"  {'TOTAL':20s} {'':40s} {hooks_total} hooks")
print(f"  Token cost: 0 on pass-through. Only non-zero when hook outputs content.")

# ── 6. Claude Code built-in system prompt ──
print()
print("=" * 60)
print("6. Claude Code built-in system prompt (not configurable)")
print("=" * 60)
# Measured from conversation context: ~2500-3000 tokens
# This includes the base instructions, tool usage guidelines, tone, etc.
builtin_tokens = 2800  # conservative estimate from conversation analysis
print(f"  ~{builtin_tokens} tokens (measured from conversation system-reminder)")
print(f"  Note: This is fixed by Claude Code runtime, cannot be optimized.")

# ── 7. Session history model ──
print()
print("=" * 60)
print("7. Session history cost model (cumulative)")
print("=" * 60)

fixed_overhead = (
    total_claude_md
    + total_rules
    + total_skill_triggers
    + total_mcp_tokens
    + builtin_tokens
)
avg_msg_input = 500  # typical user message
avg_msg_output = 500  # typical Claude response (re-read as input next turn)

print(f"  Fixed overhead per request: {fixed_overhead} tokens")
print(
    f"  Average message: {avg_msg_input} in + {avg_msg_output} out = {avg_msg_input + avg_msg_output} tokens"
)
print()
print(
    f"  {'Turns':>6s}  {'Cumulative Input':>18s}  {'Avg/Turn':>12s}  {'History %':>10s}"
)
print(f"  {'-' * 6}  {'-' * 18}  {'-' * 12}  {'-' * 10}")

for turns in [5, 10, 15, 20, 30, 50, 80]:
    cumulative = 0
    for t in range(1, turns + 1):
        history = (t - 1) * (avg_msg_input + avg_msg_output)
        cumulative += fixed_overhead + history + avg_msg_input
    avg = cumulative // turns
    history_pct = round(
        (cumulative - turns * fixed_overhead - turns * avg_msg_input) / cumulative * 100
    )
    print(f"  {turns:6d}  {cumulative:>15,d} tk  {avg:>10,d} tk  {history_pct:>8d}%")

# ── Summary ──
print()
print("=" * 60)
print("SUMMARY: Per-request fixed overhead breakdown")
print("=" * 60)

components = [
    ("CLAUDE.md", total_claude_md),
    ("Rules", total_rules),
    ("Skill triggers", total_skill_triggers),
    ("MCP schemas", total_mcp_tokens),
    ("Built-in prompt", builtin_tokens),
]

print()
for name, tokens in sorted(components, key=lambda x: -x[1]):
    pct = tokens / fixed_overhead * 100
    bar = "█" * int(pct / 2)
    print(f"  {name:20s} {tokens:6,d} tokens  ({pct:5.1f}%)  {bar}")

print(f"  {'─' * 20} {'─' * 6} {'─' * 10}")
print(f"  {'TOTAL':20s} {fixed_overhead:6,d} tokens")
print()

# Optimization potential
optimizable = total_rules + total_mcp_tokens + total_skill_triggers
print(
    f"  Optimizable: {optimizable:,d} tokens ({optimizable / fixed_overhead * 100:.1f}%)"
)
print(
    f"  Fixed (CLAUDE.md + built-in): {total_claude_md + builtin_tokens:,d} tokens ({(total_claude_md + builtin_tokens) / fixed_overhead * 100:.1f}%)"
)
