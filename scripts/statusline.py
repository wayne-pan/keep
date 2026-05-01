#!/usr/bin/env python3
"""Native Statusline — replaces claude-hud plugin.

Reads stdin JSON from Claude Code + transcript JSONL to render a 3-line status.
Zero external dependencies (stdlib only).

Usage: configured as statusLine.command in settings.json
  python3 ~/.claude/scripts/statusline.py
"""

import json
import os
import subprocess
import sys
from collections import defaultdict
from datetime import datetime

# ── ANSI Colors ──
CYAN = "\033[0;36m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
DIM = "\033[2m"
BOLD = "\033[1m"
RED = "\033[0;31m"
NC = "\033[0m"
MAGENTA = "\033[0;35m"
BLUE = "\033[0;34m"
B_GREEN = "\033[1;32m"
B_CYAN = "\033[1;36m"
B_YELLOW = "\033[1;33m"
B_RED = "\033[1;31m"
SEP = f"{DIM}│{NC}"  # visual separator

# ── Model Pricing ──
# Built-in fallback (loaded from pricing.json if available)
_BUILTIN_PRICING = {
    "opus": {"in": 15, "out": 75},
    "sonnet": {"in": 3, "out": 15},
    "haiku": {"in": 0.8, "out": 4},
    "glm-5": {"in": 0.5, "out": 0.5},
    "deepseek": {"in": 0.27, "out": 1.10},
    "kimi": {"in": 0.6, "out": 0.6},
    "qwen3": {"in": 0.5, "out": 2.0},
}
_BUILTIN_REF = "sonnet"
_BUILTIN_CONTEXTS = {
    "opus": 200_000,
    "sonnet": 200_000,
    "haiku": 200_000,
    "glm-5": 200_000,
    "glm-4": 128_000,
    "deepseek": 128_000,
    "kimi": 256_000,
    "qwen3": 262_144,
    "qwen2.5": 131_072,
    "gpt-4o": 128_000,
    "gpt-4.1": 1_000_000,
    "o3": 200_000,
    "o4-mini": 200_000,
    "gemini": 1_000_000,
}


def load_pricing():
    """Load pricing + context sizes + cache multipliers from pricing.json."""
    pricing_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "pricing.json"
    )
    try:
        with open(pricing_path) as f:
            data = json.load(f)
        models = {}
        contexts = {}
        cache_mults = {}
        global_write = data.get("_cache", {}).get("write_mult", 1.25)
        global_read = data.get("_cache", {}).get("read_mult", 0.10)
        ref = data.get("_reference", {}).get("model", _BUILTIN_REF)
        for key, val in data.get("models", {}).items():
            if isinstance(val, dict) and "in" in val and "out" in val:
                models[key] = {"in": val["in"], "out": val["out"]}
                if "context" in val:
                    contexts[key] = val["context"]
                cache_mults[key] = {
                    "write": val.get("cache_write_mult", global_write),
                    "read": val.get("cache_read_mult", global_read),
                }
        return models, contexts, cache_mults, ref
    except (OSError, json.JSONDecodeError, KeyError):
        cache_mults = {k: {"write": 1.25, "read": 0.10} for k in _BUILTIN_PRICING}
        return (
            dict(_BUILTIN_PRICING),
            dict(_BUILTIN_CONTEXTS),
            cache_mults,
            _BUILTIN_REF,
        )


(
    PRICING,
    CONTEXT_SIZES,
    CACHE_MULTS,
    REFERENCE_MODEL,
) = load_pricing()

# Fixed compact token limit for all models (trigger compaction earlier to save cost)
COMPACT_TOKEN_LIMIT = 180_000


def get_session_start(path):
    """Read the first timestamp from the beginning of the transcript."""
    try:
        with open(path, "r") as f:
            for i, line in enumerate(f):
                if i > 20:
                    break
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                    ts = entry.get("timestamp")
                    if ts:
                        return ts
                except json.JSONDecodeError:
                    continue
    except (OSError, IOError):
        pass
    return None


def parse_transcript(path):
    """Parse transcript JSONL, reading only last ~200 lines for performance."""
    result = {
        "session_tokens": {"input": 0, "output": 0, "cache_write": 0, "cache_read": 0},
        "last_turn_tokens": {"input": 0, "output": 0},
        "tools": defaultdict(lambda: {"count": 0}),
        "todos": [],
        "session_start": None,
    }

    if not path or not os.path.isfile(path):
        return result

    # Get real session start from file beginning
    result["session_start"] = get_session_start(path)

    lines = []
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            if size > 65536:
                f.seek(-65536, 2)
            else:
                f.seek(0)
            raw = f.read().decode("utf-8", errors="replace")
            lines = raw.split("\n")
    except (OSError, IOError):
        return result

    last_usage = None
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue

        entry_type = entry.get("type", "")

        # Only process assistant messages
        if entry_type != "assistant":
            continue

        msg = entry.get("message", {})
        usage = msg.get("usage", {})

        # Token usage
        if usage:
            result["session_tokens"]["input"] += usage.get("input_tokens", 0)
            result["session_tokens"]["output"] += usage.get("output_tokens", 0)
            result["session_tokens"]["cache_write"] += usage.get(
                "cache_creation_input_tokens", 0
            )
            result["session_tokens"]["cache_read"] += usage.get(
                "cache_read_input_tokens", 0
            )
            last_usage = usage

        # Tool calls + Todos
        for block in msg.get("content", []):
            if block.get("type") == "tool_use":
                name = block.get("name", "?")
                result["tools"][name]["count"] += 1

                if name == "TaskCreate":
                    inp = block.get("input", {})
                    result["todos"].append(
                        {"subject": inp.get("subject", "?"), "status": "pending"}
                    )
                elif name == "TaskUpdate":
                    inp = block.get("input", {})
                    new_status = inp.get("status", "")
                    if new_status:
                        for todo in reversed(result["todos"]):
                            if new_status in ("completed", "in_progress"):
                                todo["status"] = new_status
                                break

    # Last turn tokens
    if last_usage:
        result["last_turn_tokens"]["input"] = last_usage.get("input_tokens", 0)
        result["last_turn_tokens"]["output"] = last_usage.get("output_tokens", 0)

    return result


def get_git_status(cwd):
    """Get git branch and dirty status."""
    if not cwd or not os.path.isdir(cwd):
        return None, False
    try:
        r = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=3,
        )
        branch = r.stdout.strip()
        r2 = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=3,
        )
        dirty = r2.returncode == 0 and bool(r2.stdout.strip())
        return branch or None, dirty
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return None, False


def count_configs(cwd):
    """Count CLAUDE.md / rules / hooks / MCP files in ~/.claude."""
    claude_dir = os.path.expanduser("~/.claude")
    parts = []
    for name in ["CLAUDE.md", "NTO.md"]:
        if os.path.isfile(os.path.join(cwd, name)):
            parts.append(name)
    for d in ["rules", "hooks"]:
        dp = os.path.join(claude_dir, d)
        if os.path.isdir(dp):
            n = len([f for f in os.listdir(dp) if not f.startswith(".")])
            if n:
                parts.append(f"{n} {d}")
    # MCP servers
    claude_json = os.path.expanduser("~/.claude.json")
    if os.path.isfile(claude_json):
        try:
            with open(claude_json) as f:
                data = json.load(f)
            n_mcp = len(data.get("mcpServers", {}))
            if n_mcp:
                parts.append(f"{n_mcp} MCPs")
        except (json.JSONDecodeError, OSError):
            pass
    return " | ".join(parts)


def estimate_cost(model_name, tokens):
    """Estimate cost based on model pricing table with per-model cache multipliers."""
    name_lower = model_name.lower()
    tier = None
    key = None
    for k in PRICING:
        if k in name_lower:
            tier = PRICING[k]
            key = k
            break
    if not tier:
        return None

    cache = CACHE_MULTS.get(key, {"read": 0.10, "write": 1.25})

    inp_cost = tokens["input"] / 1_000_000 * tier["in"]
    out_cost = tokens["output"] / 1_000_000 * tier["out"]
    cache_w_cost = tokens["cache_write"] / 1_000_000 * tier["in"] * cache["write"]
    cache_r_cost = tokens["cache_read"] / 1_000_000 * tier["in"] * cache["read"]
    return inp_cost + out_cost + cache_w_cost + cache_r_cost


def fmt_tokens(n):
    """Format token count: 1500 -> 1.5k, 2700000 -> 2.7M."""
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}k"
    return str(n)


def fmt_duration(start_iso):
    """Format session duration from ISO timestamp."""
    if not start_iso:
        return ""
    try:
        ts = start_iso.replace("Z", "+00:00")
        start = datetime.fromisoformat(ts)
        now = datetime.now(start.tzinfo)
        delta = now - start
        total_min = int(delta.total_seconds() / 60)
        if total_min < 1:
            return "<1m"
        if total_min < 60:
            return f"{total_min}m"
        h, m = divmod(total_min, 60)
        return f"{h}h{m}m"
    except (ValueError, TypeError):
        return ""


def get_context_size(model_name):
    """Get context window size from loaded CONTEXT_SIZES."""
    name_lower = model_name.lower()
    for key, size in CONTEXT_SIZES.items():
        if key in name_lower:
            return size
    return 200_000  # default


def context_bar(pct, model_name, total_ctx=None, compact_limit=None):
    if total_ctx is None:
        total_ctx = get_context_size(model_name)
    used_ctx = int(total_ctx * pct / 100)

    # Effective limit: min(compact_limit, total_ctx)
    eff_limit = compact_limit if compact_limit and compact_limit < total_ctx else None

    # Bar width based on effective limit if set
    if eff_limit:
        fill_pct = min(used_ctx / eff_limit * 100, 100)
    else:
        fill_pct = pct
    filled = min(int(fill_pct / 100 * 10), 10)
    empty = 10 - filled

    bar = "█" * filled + "░" * empty

    # Color: relative to compact limit if set
    if eff_limit:
        if fill_pct < 60:
            color = B_GREEN
        elif fill_pct < 80:
            color = GREEN
        elif fill_pct < 95:
            color = B_YELLOW
        else:
            color = B_RED
    else:
        if pct < 50:
            color = B_GREEN
        elif pct < 70:
            color = GREEN
        elif pct < 90:
            color = B_YELLOW
        else:
            color = B_RED

    usage = f"{fmt_tokens(used_ctx)}/{fmt_tokens(total_ctx)}"
    limit_str = f" {DIM}cap:{fmt_tokens(eff_limit)}{NC}" if eff_limit else ""
    return f"{color}{bar}{NC} {usage}{limit_str} {DIM}({pct:.0f}%){NC}"


def cache_ratio(st):
    """Calculate cache hit ratio: cache_read / (input + cache_read) * 100."""
    total_input = st["input"] + st["cache_read"]
    if total_input == 0:
        return None
    return st["cache_read"] / total_input * 100


def render(ctx):
    """Render 3-line statusline with enhanced colors."""
    data = ctx["stdin"]
    transcript = ctx["transcript"]
    model = data.get("model", {}).get("display_name", "?")
    cwd = data.get("cwd", "")

    # Context — prefer real total from stdin, fallback to pricing.json
    cw = data.get("context_window", {})
    used_pct = (cw.get("used_percentage") or 0) if cw else 0
    total_ctx = (cw.get("total_tokens") or None) if cw else None

    # Compact limit (fixed for all models)
    compact_limit = COMPACT_TOKEN_LIMIT

    # Git
    branch, dirty = ctx.get("git", (None, False))
    git_str = ""
    if branch:
        dirty_mark = f"{B_RED}*{NC}" if dirty else ""
        git_str = f" {SEP} {B_CYAN}git:{branch}{dirty_mark}{NC}"

    # Duration
    duration = fmt_duration(transcript.get("session_start"))

    # ── Line 1: model + project + git + context + duration ──
    proj = f"{BOLD}{os.path.basename(cwd)}{NC}" if cwd else ""
    line1 = f"  {B_CYAN}{model}{NC}"
    if proj:
        line1 += f" {SEP} {proj}"
    line1 += git_str
    line1 += f" {SEP} Context {context_bar(used_pct, model, total_ctx, compact_limit)}"
    if duration:
        line1 += f" {SEP} ⏱️ {DIM}{duration}{NC}"

    # ── Line 2: tokens + cache ratio + cost ──
    st = transcript["session_tokens"]
    total = st["input"] + st["output"] + st["cache_write"] + st["cache_read"]
    lt = transcript["last_turn_tokens"]
    native_cost = data.get("cost", {}).get("total_cost_usd")

    # Total tokens (bold)
    line2 = f"  {DIM}Tokens{NC} {B_YELLOW}{fmt_tokens(total)}{NC}"

    # Breakdown — always show
    line2 += f" {SEP} in:{CYAN}{fmt_tokens(st['input'])}{NC} out:{B_GREEN}{fmt_tokens(st['output'])}{NC}"

    # Cache breakdown + hit ratio — always show
    cr = cache_ratio(st)
    cache_detail = f"w:{fmt_tokens(st['cache_write'])} r:{fmt_tokens(st['cache_read'])}"
    cr_val = cr if cr is not None else 0
    if cr_val >= 80:
        cr_color = B_GREEN
    elif cr_val >= 50:
        cr_color = B_YELLOW
    else:
        cr_color = B_RED
    line2 += f" {SEP} cache:{MAGENTA}{cache_detail}{NC} hit:{cr_color}{cr_val:.0f}%{NC}"

    # Last turn — always show
    line2 += f" {SEP} last:{CYAN}{fmt_tokens(lt['input'])}{NC}/{B_GREEN}{fmt_tokens(lt['output'])}{NC}"

    # Cost: show session cost + total
    # Anthropic: use native cost (accurate from API). Third-party: use estimate.
    session_est = estimate_cost(model, st)
    session_str = f"~${session_est:.2f}" if session_est is not None else ""

    is_anthropic = any(
        k in model.lower() for k in ("claude", "opus", "sonnet", "haiku")
    )

    if native_cost is not None and is_anthropic:
        total_str = f"${native_cost:.2f}"
    elif session_est is not None:
        total_str = f"~${session_est:.2f}"
    else:
        total_str = ""

    cost_parts = []
    if session_str and total_str and session_str != total_str:
        cost_parts.append(f"session:{B_GREEN}{session_str}{NC}")
        cost_parts.append(f"total:{B_YELLOW}{total_str}{NC}")
    elif total_str:
        cost_parts.append(f"{B_YELLOW}{total_str}{NC}")

    if cost_parts:
        line2 += f" {SEP} {(' ' + SEP + ' ').join(cost_parts)}"

    # ── Line 3: tools + config + todos ──
    tools = transcript["tools"]
    tool_parts = []
    for name, info in sorted(tools.items(), key=lambda x: -x[1]["count"]):
        tool_parts.append(f"{B_GREEN}✓{NC} {name} {DIM}×{info['count']}{NC}")

    # Config count
    config_str = count_configs(cwd)
    if config_str:
        tool_parts.append(f"{DIM}{config_str}{NC}")

    # Todos
    todos = transcript["todos"]
    if todos:
        done = sum(1 for t in todos if t["status"] == "completed")
        total_t = len(todos)
        all_done = done == total_t
        sym = f"{B_GREEN}✓{NC}" if all_done else f"{B_YELLOW}●{NC}"
        tool_parts.append(f"{sym} Todos {BOLD}{done}/{total_t}{NC}")

    line3 = (f"  {(' ' + SEP + ' ').join(tool_parts)}") if tool_parts else ""

    # Output
    lines = [line1, line2]
    if line3:
        lines.append(line3)
    print("\n".join(lines), flush=True)


def main():
    stdin_raw = sys.stdin.read()

    if not stdin_raw.strip():
        sys.exit(0)

    import traceback

    err_log = os.path.join(os.path.dirname(os.path.abspath(__file__)), "statusline.err")

    try:
        data = json.loads(stdin_raw)
        transcript_path = data.get("transcript_path", "")
        cwd = data.get("cwd", "")
        transcript = parse_transcript(transcript_path)
        git = get_git_status(cwd)
        render({"stdin": data, "transcript": transcript, "git": git})
    except Exception as e:
        with open(err_log, "w") as f:
            f.write(traceback.format_exc())
        sys.stdout.write(f"statusline error: {e}\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
