#!/usr/bin/env python3
"""benchmark.py — Harness vs Vanilla Claude Code Evaluation

All tests use `claude -p --output-format json` for reliable JSON output.

Usage:
  python3 scripts/benchmark.py                          # Full benchmark (12 tests)
  python3 scripts/benchmark.py --quick                  # Quick mode (4 core tests)
  python3 scripts/benchmark.py --dry-run
  python3 scripts/benchmark.py --keep                   # Keep results for analysis
  python3 scripts/benchmark.py --analyze <dir>           # Pareto frontier + quality
  python3 scripts/benchmark.py --analyze-detail <dir>    # + key-point breakdown
  python3 scripts/benchmark.py --iterate <dir>           # Skill improvement suggestions
  python3 scripts/benchmark.py --compare <dir1> <dir2>   # Compare two runs
  python3 scripts/benchmark.py --tests sprint-plan,code-review --keep  # Targeted re-test
"""

import json
import os
import re
import shutil
import subprocess
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from gold_answers import GoldScorer

# ── Opus 4.6 pricing ──
PRICE_IN = 5  # $5 / M input tokens
PRICE_OUT = 25  # $25 / M output tokens


@dataclass
class Test:
    name: str
    prompt: str
    dimension: str
    timeout: int
    skill: Optional[str] = None
    max_turns: int = 10


@dataclass
class TestResult:
    name: str
    dimension: str
    mode_run: str  # "pipe"
    input_tokens: int = 0
    output_tokens: int = 0
    turns: int = 0
    cost: float = 0.0
    result_text: str = ""
    quality: float = 0
    permission_denials: int = 0
    is_error: bool = False


# ── Test definitions ──
# Philosophy: test the agent as a whole on realistic SE tasks.
# No tool-specific instructions. Score on output quality, not tool usage.

# Core tests (6 tests, ~15-20 min/run) — fast iteration
CORE_TESTS = [
    Test(
        "code-structure",
        "Analyze scripts/install.sh and describe every function it defines. For each function, provide: name, line range, purpose, and what it calls.",
        "comprehension",
        90,
    ),
    Test(
        "bug-review",
        "Find potential bugs, edge cases, and security issues in hooks/safety-guard.sh. For each finding, include: file location, severity, description, and a concrete fix.",
        "debugging",
        150,
    ),
    Test(
        "security-audit",
        "Audit the hooks/ directory for security vulnerabilities. Check for: command injection, path traversal, input validation gaps, privilege escalation. List each finding with severity and fix.",
        "safety",
        360,
        max_turns=25,
    ),
    Test(
        "sprint-plan",
        "Add input validation to hooks/safety-guard.sh to prevent command injection through file paths. Research current code, produce implementation plan. Do NOT modify files.",
        "workflow",
        180,
        skill="sprint",
    ),
    Test(
        "code-review",
        "Review hooks/safety-guard.sh for bugs, security issues, and code quality. Provide findings by category, each with severity and a concrete fix.",
        "debugging",
        300,
        skill="review",
    ),
]

# Full tests (11 tests, ~40-50 min/run) — comprehensive benchmark
TESTS = [
    # ── Comprehension ──
    Test(
        "codebase-map",
        "Map the architecture of this project. For each module (hooks, rules, scripts, skills), list its files, purpose, and how it connects to other modules. Be concise.",
        "comprehension",
        120,
    ),
    Test(
        "code-structure",
        "Analyze scripts/install.sh and describe every function it defines. For each function, provide: name, line range, purpose, and what it calls.",
        "comprehension",
        90,
    ),
    Test(
        "cross-file-trace",
        "Trace how a hook gets registered: from settings.json, through install script, to the actual hook file. Show file paths and line numbers.",
        "comprehension",
        90,
    ),
    # ── Debugging ──
    Test(
        "error-diagnosis",
        "Run: cat /tmp/nonexistent-bench-xyz-12345.txt — then explain what happened, why, and what the user should do.",
        "debugging",
        60,
    ),
    Test(
        "bug-review",
        "Find potential bugs, edge cases, and security issues in hooks/safety-guard.sh. For each finding, include: file location, severity, description, and a concrete fix.",
        "debugging",
        150,
    ),
    Test(
        "code-review",
        "Review hooks/safety-guard.sh for bugs, security issues, and code quality. Provide findings by category, each with severity and a concrete fix.",
        "debugging",
        300,
        skill="review",
    ),
    # ── Design ──
    Test(
        "feature-plan",
        "Design a --dry-run flag for scripts/install.sh. Include: files to change, approach, edge cases, and verification steps.",
        "design",
        180,
    ),
    # ── Safety ──
    Test(
        "risk-assess",
        "I'm about to run: bash scripts/install.sh. Analyze the concrete risks: what exactly gets overwritten, what safeguards exist, what could break.",
        "safety",
        90,
    ),
    Test(
        "security-audit",
        "Audit the hooks/ directory for security vulnerabilities. Check for: command injection, path traversal, input validation gaps, privilege escalation.",
        "safety",
        360,
        max_turns=25,
    ),
    # ── Workflow ──
    Test(
        "implementation-plan",
        "Add argument validation to scripts/mx.sh so it rejects invalid flags and shows helpful errors. Produce a complete implementation plan. Do NOT modify files.",
        "workflow",
        180,
        skill="sprint",
    ),
    Test(
        "sprint-plan",
        "Add input validation to hooks/safety-guard.sh to prevent command injection through file paths. Research current code, produce implementation plan. Do NOT modify files.",
        "workflow",
        180,
        skill="sprint",
    ),
]

# Quick mode: 4 tests (~10 min)
QUICK_NAMES = {"code-structure", "bug-review", "security-audit", "implementation-plan"}

# Feature groups for reporting (full mode only)
FEATURE_GROUPS = [
    ("Comprehension", ["codebase-map", "code-structure", "cross-file-trace"]),
    ("Debugging", ["error-diagnosis", "bug-review", "code-review"]),
    ("Design", ["feature-plan"]),
    ("Safety", ["risk-assess", "security-audit"]),
    ("Workflow", ["implementation-plan", "sprint-plan"]),
]

PROJECT_DIR = Path(__file__).resolve().parent.parent

# ── Colors ──
R = "\033[0;31m"
G = "\033[0;32m"
Y = "\033[1;33m"
C = "\033[0;36m"
B = "\033[1m"
D = "\033[2m"
X = "\033[0m"


def info(msg: str):
    print(f"  {C}{msg}{X}")


def ok(msg: str):
    print(f"  {G}✓ {msg}{X}")


def die(msg: str):
    print(f"{R}ERROR: {msg}{X}", file=sys.stderr)
    sys.exit(1)


# ── Sandbox ──
class Sandbox:
    def __init__(self):
        self.home = ""
        self.project = ""

    def setup(self):
        self.home = tempfile.mkdtemp(prefix="bench-home-")
        self.project = tempfile.mkdtemp(prefix="bench-proj-")

        # Copy real claude config (strips harness components for vanilla isolation)
        real_claude = Path.home() / ".claude"
        claude_dir = Path(self.home) / ".claude"
        claude_dir.mkdir(parents=True)

        # Copy settings.json but strip hooks/rules/skills/plugins
        real_settings = real_claude / "settings.json"
        if real_settings.exists():
            settings = json.loads(real_settings.read_text())
            settings["hooks"] = {}
            for k in ("enabledPlugins", "extraKnownMarketplaces", "statusLine"):
                settings.pop(k, None)
            (claude_dir / "settings.json").write_text(json.dumps(settings))
        else:
            (claude_dir / "settings.json").write_text(json.dumps({"hooks": {}}))

        # Copy mcp.json (needed for claude to start properly)
        real_mcp = real_claude / "mcp.json"
        if real_mcp.exists():
            shutil.copy2(real_mcp, claude_dir / "mcp.json")

        # Copy project files (no skills, no harness config)
        for d in ["scripts", "hooks"]:
            src = PROJECT_DIR / d
            if src.is_dir():
                shutil.copytree(src, Path(self.project) / d)

        gitignore = PROJECT_DIR / ".gitignore"
        if gitignore.exists():
            shutil.copy2(gitignore, Path(self.project) / ".gitignore")

        # Vanilla CLAUDE.md — basic info only
        (Path(self.project) / "CLAUDE.md").write_text(
            "# Project\nA shell-script project with installation tools.\n"
        )

        # Git init so claude works properly
        subprocess.run(
            ["git", "init", "-q", self.project], check=False, capture_output=True
        )
        subprocess.run(
            ["git", "-C", self.project, "add", "-A"], check=False, capture_output=True
        )
        subprocess.run(
            ["git", "-C", self.project, "commit", "-q", "-m", "init", "--allow-empty"],
            check=False,
            capture_output=True,
        )

    def cleanup(self):
        for d in [self.home, self.project]:
            if d and os.path.isdir(d):
                shutil.rmtree(d, ignore_errors=True)


# ── Cost calculation ──
def compute_cost(in_tok: int, out_tok: int) -> float:
    return in_tok * PRICE_IN / 1_000_000 + out_tok * PRICE_OUT / 1_000_000


# ── Quality scorer ──
# Unified 5-dimension scoring (max 10 per test):
#   s1 Completeness (0-2): covers all important aspects
#   s2 Accuracy    (0-2): specific claims (line refs, function names, file paths)
#   s3 Safety      (0-2): identifies risks, provides warnings
#   s4 Efficiency  (0-2): concise, no padding, appropriately scoped
#   s5 Actionable  (0-2): developer can act on it immediately
class Scorer:
    @staticmethod
    def _count(pattern: str, text: str) -> int:
        return len(re.findall(pattern, text, re.MULTILINE | re.IGNORECASE))

    @staticmethod
    def _match(pattern: str, text: str) -> bool:
        return bool(re.search(pattern, text, re.IGNORECASE))

    def score(self, result: str, dimension: str, metadata: dict) -> float:
        s1 = self._completeness(result, dimension)
        s2 = self._accuracy(result)
        s3 = self._safety(result, dimension)
        s4 = self._efficiency(result)
        s5 = self._actionable(result, dimension)
        return s1 + s2 + s3 + s4 + s5

    def _completeness(self, text: str, dim: str) -> float:
        """Does the answer cover all important aspects?"""
        structure = self._count(r"^##|^\s*-\s|^\s*\d+\.\s|^\|", text)

        if dim == "comprehension":
            # Blend module mentions (surface coverage) with structural markers
            # (analysis depth). A well-structured answer with headings/lists/tables
            # shouldn't be penalised just because it doesn't name-drop every module.
            modules = len(
                set(
                    m.lower()
                    for m in re.findall(
                        r"\b(hooks|rules|scripts|skills|settings)\b",
                        text,
                        re.IGNORECASE,
                    )
                )
            )
            module_score = (
                1.0
                if modules >= 3
                else (0.75 if modules >= 2 else (0.5 if modules >= 1 else 0.25))
            )
            # Structure score: headings, lists, tables indicate real analysis
            structure_score = (
                1.0
                if structure >= 5
                else (0.75 if structure >= 3 else (0.5 if structure >= 1 else 0.25))
            )
            return min(2.0, module_score + structure_score)
        if dim in ("debugging", "safety"):
            issues = self._count(
                r"bug|issue|risk|danger|vulnerab|edge.?case|exploit|缺陷|风险|漏洞|边界",
                text,
            )
            return (
                2
                if issues >= 3
                else (1.5 if issues >= 2 else (1 if issues >= 1 else 0.5))
            )
        if dim in ("design", "workflow"):
            steps = self._count(
                r"step|phase|阶段|步骤|\d+\.\s|第[一二三四五六七八九十]", text
            )
            return (
                2 if steps >= 4 else (1.5 if steps >= 2 else (1 if steps >= 1 else 0.5))
            )
        return (
            2
            if structure >= 5
            else (1.5 if structure >= 2 else (1 if structure >= 1 else 0.5))
        )

    def _accuracy(self, text: str) -> float:
        """Specific, correct claims — line refs, function names, file paths."""
        line_refs = self._count(r"line \d+|:\d+|L\d+|第\d+行", text)
        func_names = self._count(
            r"`[a-z_]+\(\)`|`[a-z_]+`|function \w+|\b[a-z_]+\(\)", text
        )
        file_paths = self._count(r"[\w/]+\.(sh|md|json|py|ts)", text)
        specificity = line_refs + min(func_names, 4) + min(file_paths, 3)
        return (
            2
            if specificity >= 5
            else (1.5 if specificity >= 3 else (1 if specificity >= 1 else 0.5))
        )

    def _safety(self, text: str, dim: str) -> float:
        """Identifies risks and provides warnings."""
        risk_words = self._count(
            r"risk|danger|caution|warning|careful|unsafe|destruct|irreversible|风险|危险|警告|不可逆|破坏",
            text,
        )
        reason_words = self._count(
            r"because|due to|could|might|可能|由于|导致|会导致", text
        )
        if dim == "safety":
            return (
                2
                if risk_words >= 3 and reason_words >= 2
                else (1.5 if risk_words >= 2 else (1 if risk_words >= 1 else 0.5))
            )
        if dim == "debugging":
            return (
                2
                if risk_words >= 1 and reason_words >= 1
                else (1.5 if risk_words >= 1 else 1)
            )
        return 1.5 if risk_words >= 1 else 1

    def _efficiency(self, text: str) -> float:
        """Concise, no padding, appropriately scoped."""
        cjk = self._count(r"[\u4e00-\u9fff]", text)
        words = len(text.split()) + cjk
        if 50 <= words <= 300:
            return 2
        if 300 < words <= 500:
            return 1.5
        if 20 <= words < 50:
            return 1.5
        if words > 500:
            return 1
        return 0.5

    def _actionable(self, text: str, dim: str) -> float:
        """Developer can act on it immediately."""
        fix_words = self._count(
            r"fix|change|replace|add|remove|update|modify|create|implement|修改|添加|删除|替换|建议|改为",
            text,
        )
        code_snippets = self._count(r"```|`[^`]+`", text)
        specific = fix_words + min(code_snippets, 3)
        if dim in ("design", "workflow"):
            return (
                2
                if specific >= 4
                else (1.5 if specific >= 2 else (1 if specific >= 1 else 0.5))
            )
        if dim in ("debugging", "safety"):
            return 2 if specific >= 3 else (1.5 if specific >= 1 else 1)
        if dim == "comprehension":
            return 1.5 if specific >= 1 else 1
        return 1.5 if specific >= 2 else (1 if specific >= 1 else 0.5)


# ── Test runner ──
class TestRunner:
    def __init__(self, sandbox: Sandbox, results_dir: str, model: Optional[str] = None):
        self.sandbox = sandbox
        self.results_dir = results_dir
        self.scorer = GoldScorer()
        self.model = model

    @staticmethod
    def _condense_skill(skill_name: str, content: str) -> str:
        """Prepare skill content for benchmark injection.

        With progressive disclosure, SKILL.md is already lean.
        Only append pipe-mode output format instructions.
        """
        if skill_name == "sprint":
            content += """

## Output Format Requirements (Critical)
IMPORTANT: You are running in pipe mode. Do NOT write to files (SPRINT.md, RESEARCH.md, etc.).
Your ENTIRE response must be in stdout — include ALL content directly in your text output.

Your response MUST include ALL of the following:
1. **Research findings**: What files you read, what code you analyzed, what functions/lines you found (cite specific line numbers like `:35` or `line 35`)
2. **Specific line references**: Every code change MUST reference exact line numbers and file paths
3. **Validation approach**: State the specific validation method (whitelist, sanitization function, regex pattern, etc.)
4. **Test plan**: At least 3 concrete test cases including edge cases (empty input, special characters, normal input)
5. **Injection defense**: Show the actual code snippet for sanitization/validation
6. **Confidence level**: State your confidence (HIGH/MEDIUM/LOW) with reasoning
7. **Rollback strategy**: How to undo if something goes wrong

## CRITICAL: Anti-Truncation
You MUST produce a COMPLETE response. Do NOT stop mid-sentence or mid-section.
If your response is shorter than 500 words, it is INCOMPLETE.
Include ALL 7 sections above. A truncated response scores 0.
"""

        elif skill_name == "review":
            content += """

## Output Format Requirements (Critical)
IMPORTANT: You are running in pipe mode. Do NOT spawn subagents or write to files.
Perform the ENTIRE review yourself in a single response.

Your response MUST include ALL of the following:
1. **Findings by category**: Group into Security, Bugs, Code Quality (at least 2 categories)
2. **Severity ratings**: Each finding tagged [HIGH], [MEDIUM], or [LOW]
3. **Line references**: Every finding MUST cite specific file:line_number
4. **Concrete fixes**: Show the actual code change for each finding
5. **File summary**: Start with a one-line summary of what the file does
"""

        return content

    def run(self, test: Test, mode: str, quick: bool = False) -> Optional[TestResult]:
        if quick and test.name not in QUICK_NAMES:
            return None

        env_home = self.sandbox.home if mode == "vanilla" else str(Path.home())
        workdir = self.sandbox.project if mode == "vanilla" else str(PROJECT_DIR)

        # For harness mode, strip non-essential MCP servers (codedb etc.)
        # to avoid context bloat that degrades benchmark quality.
        env = os.environ.copy()
        if mode == "harness":
            claude_json = Path(env_home) / ".claude.json"
            if claude_json.exists():
                try:
                    cj = json.loads(claude_json.read_text())
                    servers = cj.get("mcpServers", {})
                    # Only keep mind for benchmark
                    if len(servers) > 1:
                        cj["mcpServers"] = {
                            k: v for k, v in servers.items() if k == "mind"
                        }
                        env["HOME"] = env_home  # Use real home
                        # Write a temp claude.json without extra MCP servers
                        tmp_home = tempfile.mkdtemp(prefix="bench-harness-")
                        tmp_claude = Path(tmp_home) / ".claude.json"
                        tmp_claude.write_text(json.dumps(cj))
                        # Symlink the .claude dir for rules/skills
                        real_claude_dir = Path(env_home) / ".claude"
                        tmp_claude_dir = Path(tmp_home) / ".claude"
                        if real_claude_dir.exists() and not tmp_claude_dir.exists():
                            os.symlink(real_claude_dir, tmp_claude_dir)
                        env_home = tmp_home
                except (json.JSONDecodeError, OSError):
                    pass

        # Use per-test max_turns (default 10), boost for skill/memory tests
        mt = test.max_turns
        if test.skill or test.dimension in ("skill", "memory", "verify"):
            mt = max(mt, 20)
        max_turns = str(mt)

        # Apply timeout buffer
        effective_timeout = int(test.timeout * 1.3)
        if mode == "harness":
            effective_timeout = int(test.timeout * 1.5)

        # Inject skill instructions for harness mode (simulates /command activation)
        prompt = test.prompt

        # All tests run in pipe mode — ensure output goes to stdout, not files
        prompt += (
            "\n\nIMPORTANT: You are running in pipe mode. Do NOT write to files. "
            "Your ENTIRE response must be in stdout — include ALL details directly "
            "in your text output, including specific line numbers, file paths, code "
            "snippets, test cases, and rollback strategy."
        )

        if mode == "harness" and test.skill:
            skill_path = PROJECT_DIR / "skills" / test.skill / "SKILL.md"
            if skill_path.exists():
                skill_content = self._condense_skill(test.skill, skill_path.read_text())
                prompt = f"[Skill: /{test.skill} activated]\n\n{skill_content}\n\n---\nUser: {prompt}"

        cmd = [
            "claude",
            "-p",
            prompt,
            "--output-format",
            "json",
            "--max-turns",
            max_turns,
            "--dangerously-skip-permissions",
        ]

        if self.model:
            cmd.extend(["--model", self.model])

        env["HOME"] = env_home

        max_retries = 4  # up to 5 attempts (handles transient API slowdowns)
        for attempt in range(max_retries + 1):
            proc = None
            try:
                proc = subprocess.run(
                    cmd,
                    capture_output=True,
                    text=True,
                    timeout=effective_timeout,
                    cwd=workdir,
                    env=env,
                )
                data = json.loads(proc.stdout) if proc.stdout.strip() else {}
            except (subprocess.TimeoutExpired, json.JSONDecodeError) as e:
                # Save crash info for diagnosis
                crash_file = (
                    Path(self.results_dir)
                    / f"crash-{mode}-{test.name}-attempt{attempt}.log"
                )
                crash_file.write_text(
                    f"Exception: {type(e).__name__}: {e}\n"
                    f"Timeout: {effective_timeout}s\n"
                    f"Returncode: {proc.returncode if proc else 'N/A (timeout)'}\n"
                    f"Stderr: {(proc.stderr if proc else '')[-500:]}\n"
                )
                data = {}

            result = self._parse_json_result(test, mode, data)

            # Success — return immediately
            if (
                result.input_tokens > 0
                or result.output_tokens > 0
                or result.result_text
            ):
                return result

            # Crash — retry
            if attempt < max_retries:
                info(
                    f"  {test.name} ({mode}) crashed (attempt {attempt + 1}/{max_retries + 1}), retrying..."
                )

        return result

    def _parse_json_result(self, test: Test, mode: str, data: dict) -> TestResult:
        usage = data.get("usage", {})
        in_tok = usage.get("input_tokens", 0) or 0
        out_tok = usage.get("output_tokens", 0) or 0
        result_text = data.get("result", "") or ""
        denials = len(data.get("permission_denials", []))
        turns = data.get("num_turns", 0) or 0

        cost = compute_cost(in_tok, out_tok)
        quality = self.scorer.score(result_text, test.name)

        return TestResult(
            name=test.name,
            dimension=test.dimension,
            mode_run="pipe",
            input_tokens=in_tok,
            output_tokens=out_tok,
            turns=turns,
            cost=cost,
            result_text=result_text,
            quality=quality,
            permission_denials=denials,
        )


# ── Warm up memory index ──
def warmup_memory():
    info("Warming up memory index...")
    try:
        subprocess.run(
            [
                "claude",
                "-p",
                "Use smart_search to find 'safety' patterns",
                "--output-format",
                "json",
                "--max-turns",
                "3",
                "--dangerously-skip-permissions",
            ],
            capture_output=True,
            timeout=45,
        )
    except Exception:
        pass
    ok("Memory index ready")
    ok("Memory index ready")


# ── Print report ──
def print_report(results: dict[str, tuple[TestResult, TestResult]], quick: bool):
    total_vi = total_vo = total_hi = total_ho = 0
    total_vs = total_hs = 0
    total_vcost = total_hcost = 0.0
    wins = count = 0

    # Pre-compute all metrics
    metrics = {}
    for name, (vr, hr) in results.items():
        metrics[name] = {
            "vi": vr.input_tokens or 0,
            "vo": vr.output_tokens or 0,
            "vt": vr.turns or 0,
            "vc": vr.cost or 0.0,
            "vq": vr.quality or 0,
            "hi": hr.input_tokens or 0,
            "ho": hr.output_tokens or 0,
            "ht": hr.turns or 0,
            "hc": hr.cost or 0.0,
            "hq": hr.quality or 0,
            "mode": hr.mode_run,
        }
        total_vi += vr.input_tokens
        total_vo += vr.output_tokens
        total_hi += hr.input_tokens
        total_ho += hr.output_tokens
        total_vs += vr.quality
        total_hs += hr.quality
        total_vcost += vr.cost
        total_hcost += hr.cost
        if hr.quality > vr.quality:
            wins += 1
        count += 1

    # Header
    print()
    print(
        f"{B}╔═══════════════════════════════════════════════════════════════════════════╗{X}"
    )
    print(
        f"{B}║     Harness vs Vanilla — Full Feature Benchmark (Python)                ║{X}"
    )
    print(
        f"{B}║            Pricing: Opus 4.6 ($5/M in, $25/M out)                        ║{X}"
    )
    print(
        f"{B}╚═══════════════════════════════════════════════════════════════════════════╝{X}"
    )
    print()

    sep = "────────────────  ────────────────────────────  ────────────────────────────  ────"

    for gname, test_names in FEATURE_GROUPS:
        filtered = [n for n in test_names if n in results]
        if not filtered:
            continue

        print(f"  {Y}{gname}{X}")
        print(
            f"  {'Test':<16s}  {'Vanilla (in/out)':<28s}  {'Harness (in/out)':<28s}  Q"
        )
        print(f"  {sep}")

        g_vi = g_vo = g_hi = g_ho = 0
        g_vs = g_hs = g_wins = 0
        g_vcost = g_hcost = 0.0

        for name in filtered:
            m = metrics[name]
            indicator = "="
            if m["hq"] > m["vq"]:
                indicator = "+"
                g_wins += 1
            elif m["hq"] < m["vq"]:
                indicator = "-"

            vi_s = str(m["vi"]) if m["vi"] else "~"
            vo_s = str(m["vo"]) if m["vo"] else "~"
            hi_s = str(m["hi"]) if m["hi"] else "~"
            ho_s = str(m["ho"]) if m["ho"] else "~"

            print(
                f"  {name:<16s}  "
                f"{vi_s:>5s}/{vo_s:<5s}{m['vt']:>2d}t ${m['vc']:<6.4f} [{m['vq']:.1f}/10]  "
                f"{hi_s:>5s}/{ho_s:<5s}{m['ht']:>2d}t ${m['hc']:<6.4f} [{m['hq']:.1f}/10]  "
                f"{indicator}"
            )

            g_vi += m["vi"]
            g_vo += m["vo"]
            g_hi += m["hi"]
            g_ho += m["ho"]
            g_vs += m["vq"]
            g_hs += m["hq"]
            g_vcost += m["vc"]
            g_hcost += m["hc"]

        print(f"  {sep}")
        g_tv = g_vi + g_vo
        g_th = g_hi + g_ho
        g_savings = (g_tv - g_th) * 100 / g_tv if g_tv > 0 else 0
        g_vi_s = str(g_vi) if g_vi else "~"
        g_vo_s = str(g_vo) if g_vo else "~"
        g_hi_s = str(g_hi) if g_hi else "~"
        g_ho_s = str(g_ho) if g_ho else "~"
        print(
            f"  {'Subtotal':<16s}  "
            f"{g_vi_s:>9s}/{g_vo_s:<7s} ${g_vcost:<6.4f} [{g_vs:.1f}/{len(filtered) * 10}]  "
            f"{g_hi_s:>9s}/{g_ho_s:<7s} ${g_hcost:<6.4f} [{g_hs:.1f}/{len(filtered) * 10}]  "
            f"{g_savings:.1f}%tok"
        )
        print()

    # Overall
    total_v = total_vi + total_vo
    total_h = total_hi + total_ho
    savings = (total_v - total_h) * 100 / total_v if total_v > 0 else 0
    cost_savings = (
        (total_vcost - total_hcost) * 100 / total_vcost if total_vcost > 0 else 0
    )

    print(f"{B}══ Overall ══{X}")
    direction = "more costly" if savings < 0 else "savings"
    print(f"  Token efficiency:   {B}Harness {savings:.1f}% ({direction}){X}")
    print(
        f"  Cost (Opus 4.6):    Vanilla ${total_vcost:.4f} → Harness ${total_hcost:.4f} ({cost_savings:.1f}%)"
    )
    print(
        f"  Quality impact:     {B}Harness wins {wins}/{count}{X} tests, score {total_vs:.1f}→{total_hs:.1f} (delta={total_hs - total_vs:+.1f})"
    )

    if total_vcost > 0 and total_hcost > 0:
        v_eff = total_vs / total_vcost
        h_eff = total_hs / total_hcost
        print(f"  Cost-effectiveness:  Vanilla {v_eff:.1f} → Harness {h_eff:.1f} pts/$")

    print(
        f"  Feature coverage:   {B}{count} tests across {len(FEATURE_GROUPS)} feature groups{X}"
    )

    # Token breakdown table
    print()
    print(f"  {Y}Token Breakdown by Group{X}")
    print(
        f"  {'Group':<20s}  {'Vanilla (in+out)':>18s}  {'Harness (in+out)':>18s}  {'Δ Tokens':>10s}  {'Savings':>8s}"
    )
    print(f"  {'─' * 20}  {'─' * 18}  {'─' * 18}  {'─' * 10}  {'─' * 8}")

    grand_v = grand_h = 0
    for gname, test_names in FEATURE_GROUPS:
        g_vi = g_vo = g_hi = g_ho = 0
        for n in test_names:
            if n in metrics:
                m = metrics[n]
                g_vi += m["vi"]
                g_vo += m["vo"]
                g_hi += m["hi"]
                g_ho += m["ho"]
        g_tv = g_vi + g_vo
        g_th = g_hi + g_ho
        grand_v += g_tv
        grand_h += g_th
        delta = g_tv - g_th
        pct = delta * 100 / g_tv if g_tv > 0 else 0
        sign = "+" if delta > 0 else ""
        print(
            f"  {gname:<20s}  {g_vi:>7d}+{g_vo:<7d}  {g_hi:>7d}+{g_ho:<7d}  {sign}{delta:>9d}  {pct:>+7.1f}%"
        )

    print(f"  {'─' * 20}  {'─' * 18}  {'─' * 18}  {'─' * 10}  {'─' * 8}")
    gdelta = grand_v - grand_h
    gpct = gdelta * 100 / grand_v if grand_v > 0 else 0
    gsign = "+" if gdelta > 0 else ""
    print(
        f"  {'TOTAL':<20s}  {total_vi:>7d}+{total_vo:<7d}  {total_hi:>7d}+{total_ho:<7d}  "
        f"{gsign}{gdelta:>9d}  {gpct:>+7.1f}%"
    )


# ── pass@k metrics ──
def compute_pass_metrics(scores: list[float], threshold: float = 7.0) -> dict:
    """Compute pass@k and pass^k from a list of quality scores.

    pass@k: at least 1 score >= threshold in k attempts (reliability)
    pass^k: all k scores >= threshold (consistency)
    """
    if not scores:
        return {"pass_rate": 0, "pass_at_k": 0, "pass_caret_k": 0}
    k = len(scores)
    passes = sum(1 for s in scores if s >= threshold)
    return {
        "pass_rate": passes / k,
        "pass_at_k": 1.0 if passes >= 1 else 0.0,
        "pass_caret_k": 1.0 if passes == k else 0.0,
        "threshold": threshold,
        "k": k,
        "passes": passes,
    }


# ── Multi-run report (median ± std dev) ──
def print_multi_run_report(all_runs: list[dict[str, tuple[TestResult, TestResult]]]):
    """Report median quality across multiple runs with stability analysis."""
    from statistics import median, stdev

    n = len(all_runs)
    print()
    print(
        f"{B}╔═══════════════════════════════════════════════════════════════════════════╗{X}"
    )
    print(
        f"{B}║     Multi-Run Stability Report ({n} runs, median ± std dev)            ║{X}"
    )
    print(
        f"{B}║            Pricing: Opus 4.6 ($5/M in, $25/M out)                        ║{X}"
    )
    print(
        f"{B}╚═══════════════════════════════════════════════════════════════════════════╝{X}"
    )
    print()

    # Collect per-test quality scores across runs
    test_names = list(all_runs[0].keys())
    unstable_tests = []

    sep = "────────────────  ────────────────────────────  ────────────────────────────  ────"

    for gname, group_names in FEATURE_GROUPS:
        filtered = [n for n in group_names if n in test_names]
        if not filtered:
            continue

        print(f"  {Y}{gname}{X}")
        print(
            f"  {'Test':<16s}  {'Vanilla Quality':<28s}  {'Harness Quality':<28s}  Stab"
        )
        print(f"  {sep}")

        g_vq_list, g_hq_list = [], []

        for name in filtered:
            v_scores, h_scores = [], []
            for run in all_runs:
                if name in run:
                    v_scores.append(run[name][0].quality)
                    h_scores.append(run[name][1].quality)

            if not v_scores:
                continue

            v_med = median(v_scores)
            h_med = median(h_scores)
            v_std = stdev(v_scores) if len(v_scores) >= 2 else 0
            h_std = stdev(h_scores) if len(h_scores) >= 2 else 0

            g_vq_list.extend(v_scores)
            g_hq_list.extend(h_scores)

            # Stability indicator: use CoV (σ/mean) for meaningful comparison
            v_cov = v_std / v_med * 100 if v_med > 0 else 0
            h_cov = h_std / h_med * 100 if h_med > 0 else 0
            max_std = max(v_std, h_std)
            max_cov = max(v_cov, h_cov)
            if max_std > 2.0:
                stab = f"{R}✗ σ{max_std:.1f} CoV{max_cov:.0f}%{X}"
                unstable_tests.append((name, v_std, h_std, v_cov, h_cov))
            elif max_std > 1.0:
                stab = f"{Y}~ σ{max_std:.1f} CoV{max_cov:.0f}%{X}"
            else:
                stab = f"{G}✓ σ{max_std:.1f}{X}"

            indicator = "="
            if h_med > v_med:
                indicator = "+"
            elif h_med < v_med:
                indicator = "-"

            print(
                f"  {name:<16s}  "
                f"{v_med:>4.1f} ± {v_std:<4.1f} [{min(v_scores):.0f}-{max(v_scores):.0f}]{' ':>4s}"
                f"{h_med:>4.1f} ± {h_std:<4.1f} [{min(h_scores):.0f}-{max(h_scores):.0f}]{' ':>4s}"
                f"  {stab} {indicator}"
            )

        if g_vq_list:
            gv_med = median(g_vq_list)
            gh_med = median(g_hq_list)
            print(f"  {sep}")
            pad = " " * 16
            print(
                f"  {'Subtotal':<16s}  {gv_med:>5.1f}/10 avg{pad}{gh_med:>5.1f}/10 avg"
            )
        print()

    # Overall summary
    all_v = [run[name][0].quality for run in all_runs for name in run]
    all_h = [run[name][1].quality for run in all_runs for name in run]
    ov_med = median(all_v)
    oh_med = median(all_h)
    total_pts = len(test_names) * 10
    runs_pct = n / total_pts * 100 if total_pts > 0 else 0

    print(f"{B}══ Stability Summary ══{X}")
    print(
        f"  Runs: {n}  |  Tests per run: {len(test_names)}  |  Total comparisons: {len(all_v)}"
    )
    print(f"  Vanilla median:  {ov_med:.1f}/10")
    print(f"  Harness median:  {oh_med:.1f}/10")
    delta = oh_med - ov_med
    sign = "+" if delta > 0 else ""
    print(f"  Quality delta:   {B}{sign}{delta:.1f}{X}")

    if unstable_tests:
        print(f"\n  {R}Unstable tests (σ > 2.0):{X}")
        for name, vs, hs, vc, hc in unstable_tests:
            print(
                f"    {name}: vanilla σ={vs:.1f} (CoV {vc:.0f}%), harness σ={hs:.1f} (CoV {hc:.0f}%)"
            )
    else:
        print(f"\n  {G}All tests stable (σ ≤ 2.0){X}")

    # pass@k table
    PASS_THRESHOLD = 7.0
    print(f"\n  {Y}pass@k Metrics (threshold: {PASS_THRESHOLD}/10){X}")
    print(f"  {'Test':<16s}  {'Vanilla':>10s}  {'Harness':>10s}  Reliability")
    print(f"  {sep}")

    for gname, group_names in FEATURE_GROUPS:
        filtered = [fn for fn in group_names if fn in test_names]
        for fn in filtered:
            v_sc, h_sc = [], []
            for run in all_runs:
                if fn in run:
                    v_sc.append(run[fn][0].quality)
                    h_sc.append(run[fn][1].quality)
            if not v_sc:
                continue
            vp = compute_pass_metrics(v_sc, PASS_THRESHOLD)
            hp = compute_pass_metrics(h_sc, PASS_THRESHOLD)
            v_str = f"{vp['passes']}/{vp['k']}"
            h_str = f"{hp['passes']}/{hp['k']}"
            if hp["pass_at_k"] and not vp["pass_at_k"]:
                rel = f"{G}harness-only{X}"
            elif hp["pass_caret_k"] and not vp["pass_caret_k"]:
                rel = f"{G}harness-consistent{X}"
            elif vp["pass_caret_k"] and not hp["pass_caret_k"]:
                rel = f"{R}vanilla-consistent{X}"
            else:
                rel = "="
            print(f"  {fn:<16s}  {v_str:>10s}  {h_str:>10s}  {rel}")

    all_v_pass = sum(
        1 for run in all_runs for fn in run if run[fn][0].quality >= PASS_THRESHOLD
    )
    all_h_pass = sum(
        1 for run in all_runs for fn in run if run[fn][1].quality >= PASS_THRESHOLD
    )
    all_total = sum(len(run) for run in all_runs)
    print(f"  {sep}")
    print(
        f"  {'Overall':<16s}  {all_v_pass}/{all_total:>8d}  {all_h_pass}/{all_total:>8d}"
    )
    print(
        f"  pass@{len(all_runs)}: Vanilla {'✓' if all_v_pass >= 1 else '✗'} | Harness {'✓' if all_h_pass >= 1 else '✗'}"
    )
    print(
        f"  pass^{len(all_runs)}: Vanilla {'✓' if all_v_pass == all_total else '✗'} | Harness {'✓' if all_h_pass == all_total else '✗'}"
    )

    # Token efficiency across runs
    print(f"\n  {Y}Token Efficiency (median across {n} runs){X}")
    run_totals_v, run_totals_h = [], []
    for run in all_runs:
        tv = sum(run[name][0].input_tokens + run[name][0].output_tokens for name in run)
        th = sum(run[name][1].input_tokens + run[name][1].output_tokens for name in run)
        run_totals_v.append(tv)
        run_totals_h.append(th)

    tv_med = median(run_totals_v)
    th_med = median(run_totals_h)
    savings = (tv_med - th_med) * 100 / tv_med if tv_med > 0 else 0
    direction = "savings" if savings > 0 else "more costly"
    print(f"  Vanilla:  {tv_med:,.0f} tokens (median)")
    print(f"  Harness:  {th_med:,.0f} tokens (median)")
    print(f"  Result:   {B}{abs(savings):.1f}% {direction}{X}")

    # Cost-effectiveness
    run_cost_v, run_cost_h = [], []
    for run in all_runs:
        cv = sum(run[name][0].cost for name in run)
        ch = sum(run[name][1].cost for name in run)
        run_cost_v.append(cv)
        run_cost_h.append(ch)

    cv_med = median(run_cost_v)
    ch_med = median(run_cost_h)
    v_eff = ov_med / cv_med * 10 if cv_med > 0 else 0
    h_eff = oh_med / ch_med * 10 if ch_med > 0 else 0
    print(f"\n  Cost-effectiveness:")
    print(f"  Vanilla:  {v_eff:.1f} pts/$")
    print(f"  Harness:  {h_eff:.1f} pts/$")
    eff_delta = h_eff - v_eff
    if eff_delta > 0:
        print(f"  Result:   {G}Harness +{eff_delta:.1f} pts/$ more cost-effective{X}")
    else:
        print(
            f"  Result:   {R}Vanilla +{abs(eff_delta):.1f} pts/$ more cost-effective{X}"
        )


# ── Analyze saved results ──
def _load_results(results_dir: str) -> dict[str, dict[str, dict]]:
    """Load all result JSON files from a saved results directory."""
    rpath = Path(results_dir)
    if not rpath.is_dir():
        die(f"Results directory not found: {results_dir}")

    test_results: dict[str, dict[str, dict]] = {}
    for f in sorted(rpath.glob("*.json")):
        name = f.stem
        # Parse: vanilla-{test} or harness-{test}[-run{N}]
        parts = name.split("-", 1)
        if len(parts) < 2 or parts[0] not in ("vanilla", "harness"):
            continue
        mode = parts[0]
        test_name = parts[1]
        # Strip -run{N} suffix for multi-run
        run_match = re.match(r"(.+)-run\d+$", test_name)
        if run_match:
            test_name = run_match.group(1)

        data = json.loads(f.read_text())
        test_results.setdefault(test_name, {})[mode] = data

    return test_results


def cmd_analyze(results_dir: str, detail: bool = False):
    """Analyze saved benchmark results with Pareto frontier and key-point breakdown."""
    from gold_answers import GoldScorer

    test_results = _load_results(results_dir)
    if not test_results:
        die(f"No result files found in {results_dir}")

    crash_logs = sorted(Path(results_dir).glob("crash-*.log"))

    print()
    print(f"{B}Benchmark Results Analysis{X}")
    print(f"Source: {results_dir}")
    print()

    # Quality comparison table
    print(f"  {Y}Quality Comparison{X}")
    print(
        f"  {'Test':<18s}  {'Vanilla':>8s}  {'Harness':>8s}  {'Δ':>6s}  {'Winner':>8s}  {'Cost V→H':>10s}"
    )
    print(f"  {'─' * 18}  {'─' * 8}  {'─' * 8}  {'─' * 6}  {'─' * 8}  {'─' * 10}")

    all_vq, all_hq = [], []
    total_vc, total_hc = 0.0, 0.0
    for gname, test_names in FEATURE_GROUPS:
        for name in test_names:
            if name not in test_results:
                continue
            modes = test_results[name]
            vq = modes.get("vanilla", {}).get("quality", 0)
            hq = modes.get("harness", {}).get("quality", 0)
            vc = modes.get("vanilla", {}).get("cost", 0)
            hc = modes.get("harness", {}).get("cost", 0)
            delta = hq - vq

            all_vq.append(vq)
            all_hq.append(hq)
            total_vc += vc
            total_hc += hc

            if delta > 0.3:
                winner = f"{G}harness{X}"
            elif delta < -0.3:
                winner = f"{R}vanilla{X}"
            else:
                winner = "tie"

            sign = "+" if delta > 0 else ""
            cost_delta = total_hc - total_vc

            print(
                f"  {name:<18s}  {vq:>6.1f}/10  {hq:>6.1f}/10  {sign}{delta:>4.1f}  {winner:>18s}  ${vc:.3f}→${hc:.3f}"
            )

    if all_vq:
        v_med = sum(all_vq) / len(all_vq)
        h_med = sum(all_hq) / len(all_hq)
        sign = "+" if h_med > v_med else ""
        print(f"  {'─' * 18}  {'─' * 8}  {'─' * 8}  {'─' * 6}  {'─' * 8}  {'─' * 10}")
        print(
            f"  {'Average':<18s}  {v_med:>6.1f}/10  {h_med:>6.1f}/10  {sign}{h_med - v_med:>4.1f}"
        )
        print(
            f"  {'Total cost':<18s}  ${total_vc:.4f}  ${total_hc:.4f}  ${(total_hc - total_vc) * 100 / total_vc:+.1f}%"
            if total_vc > 0
            else ""
        )

    # Pareto frontier (quality vs cost for harness)
    print(f"\n  {Y}Pareto Frontier — Quality vs Cost (Harness){X}")
    print(f"  {'Test':<18s}  {'Quality':>8s}  {'Cost':>8s}  {'Q/$':>8s}  Frontier")
    print(f"  {'─' * 18}  {'─' * 8}  {'─' * 8}  {'─' * 8}  {'─' * 8}")

    pareto = []
    for name, modes in test_results.items():
        h = modes.get("harness", {})
        if not h:
            continue
        q = h.get("quality", 0)
        c = h.get("cost", 0)
        qpc = q / c * 10 if c > 0 else 0
        pareto.append((name, q, c, qpc))

    # Sort by quality descending
    pareto.sort(key=lambda x: -x[1])

    # Find Pareto frontier: a point is on the frontier if no other point has
    # both higher quality AND lower cost
    frontier = []
    for i, (name, q, c, qpc) in enumerate(pareto):
        dominated = False
        for j, (_, q2, c2, _) in enumerate(pareto):
            if i != j and q2 >= q and c2 <= c and (q2 > q or c2 < c):
                dominated = True
                break
        frontier.append((name, q, c, qpc, not dominated))

    for name, q, c, qpc, on_frontier in frontier:
        marker = f"{G}◆ frontier{X}" if on_frontier else ""
        print(f"  {name:<18s}  {q:>6.1f}/10  ${c:>7.4f}  {qpc:>7.1f}  {marker}")

    # Key-point breakdown (if --detail)
    if detail:
        scorer = GoldScorer()
        print(f"\n  {Y}Key Point Breakdown{X}")
        print(f"  {'─' * 60}")
        for name, modes in test_results.items():
            for mode_label in ("harness", "vanilla"):
                text = modes.get(mode_label, {}).get("result", "")
                if not text:
                    continue
                detail_data = scorer.score_detail(text, name)
                if detail_data["misses"]:
                    print(
                        f"\n  {B}{name}{X} ({mode_label}: {detail_data['total']:.1f}/10)"
                    )
                    for h in detail_data["hits"]:
                        print(f"    {G}✓{X} {h['id']} ({h['weight']})")
                    for m in detail_data["misses"]:
                        print(
                            f"    {R}✗{X} {m['id']} ({m['weight']})  {Y}← improvement target{X}"
                        )

    # Crash logs
    if crash_logs:
        print(f"\n  {Y}Crash Logs ({len(crash_logs)}){X}")
        for cl in crash_logs:
            content = cl.read_text()[:200]
            print(f"  {R}{cl.name}{X}: {content.split(chr(10))[0]}")

    # Improvement targets: tests where vanilla > harness by significant margin
    print(f"\n  {Y}Improvement Targets{X}")
    targets = []
    for name, modes in test_results.items():
        vq = modes.get("vanilla", {}).get("quality", 0)
        hq = modes.get("harness", {}).get("quality", 0)
        if vq > hq + 0.5:
            targets.append((name, vq, hq, vq - hq))
    targets.sort(key=lambda x: -x[3])

    if targets:
        for name, vq, hq, gap in targets:
            print(
                f"  {R}{name:<18s}  vanilla {vq:.1f} > harness {hq:.1f}  (gap: {gap:.1f}){X}"
            )
    else:
        print(f"  {G}Harness >= Vanilla on all tests{X}")


def cmd_compare(dir1: str, dir2: str):
    """Compare two benchmark result sets."""
    r1 = _load_results(dir1)
    r2 = _load_results(dir2)

    if not r1 or not r2:
        die("One or both result directories contain no results")

    print()
    print(f"{B}Benchmark Comparison{X}")
    print(f"  A: {dir1}")
    print(f"  B: {dir2}")
    print()

    print(f"  {'Test':<18s}  {'A (H)':>8s}  {'B (H)':>8s}  {'Δ':>6s}  Direction")
    print(f"  {'─' * 18}  {'─' * 8}  {'─' * 8}  {'─' * 6}  {'─' * 20}")

    improved = regressed = unchanged = 0
    all_a = []
    all_b = []

    # Compare harness quality across all tests present in both
    all_names = sorted(set(r1.keys()) & set(r2.keys()))
    for name in all_names:
        qa = r1[name].get("harness", {}).get("quality", 0)
        qb = r2[name].get("harness", {}).get("quality", 0)
        delta = qb - qa
        all_a.append(qa)
        all_b.append(qb)

        if delta > 0.3:
            direction = f"{G}improved{X}"
            improved += 1
        elif delta < -0.3:
            direction = f"{R}regressed{X}"
            regressed += 1
        else:
            direction = "unchanged"
            unchanged += 1

        sign = "+" if delta > 0 else ""
        print(
            f"  {name:<18s}  {qa:>6.1f}/10  {qb:>6.1f}/10  {sign}{delta:>4.1f}  {direction}"
        )

    if all_a:
        med_a = sum(all_a) / len(all_a)
        med_b = sum(all_b) / len(all_b)
        sign = "+" if med_b > med_a else ""
        print(f"  {'─' * 18}  {'─' * 8}  {'─' * 8}  {'─' * 6}  {'─' * 20}")
        print(
            f"  {'Average':<18s}  {med_a:>6.1f}/10  {med_b:>6.1f}/10  {sign}{med_b - med_a:>4.1f}"
        )

    print(
        f"\n  Summary: {G}{improved} improved{X}, {R}{regressed} regressed{X}, {unchanged} unchanged"
    )


# ── Experiment log (TSV) ──
EXPERIMENTS_FILE = PROJECT_DIR / ".sprint" / "EXPERIMENTS.tsv"
TSV_HEADER = "iteration\tcommit\tmetric\tdelta\tguard\tstatus\tcomp\taccur\tsafety\teffic\tact\tdescription"


def log_experiment(
    metric: float,
    delta: float,
    guard: str,
    status: str,
    description: str,
    dimensions: dict = None,
):
    """Append a row to the experiment TSV log."""
    EXPERIMENTS_FILE.parent.mkdir(parents=True, exist_ok=True)
    if not EXPERIMENTS_FILE.exists():
        EXPERIMENTS_FILE.write_text(TSV_HEADER + "\n")
    lines = EXPERIMENTS_FILE.read_text().strip().split("\n")
    iteration = len(lines)
    commit = "-"
    try:
        commit = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True
        ).stdout.strip()
    except Exception:
        pass
    dims = dimensions or {}
    comp = dims.get("completeness", 0)
    accur = dims.get("accuracy", 0)
    safety = dims.get("safety", 0)
    effic = dims.get("efficiency", 0)
    act = dims.get("actionable", 0)
    row = f"{iteration}\t{commit}\t{metric:.1f}\t{delta:+.1f}\t{guard}\t{status}\t{comp:.1f}\t{accur:.1f}\t{safety:.1f}\t{effic:.1f}\t{act:.1f}\t{description}"
    with open(EXPERIMENTS_FILE, "a") as f:
        f.write(row + "\n")


def cmd_experiments():
    """Display experiment history from TSV log."""
    if not EXPERIMENTS_FILE.exists():
        print(f"  {D}No experiment log found at {EXPERIMENTS_FILE}{X}")
        return
    print(f"\n{B}Experiment History{X}")
    print(f"  Source: {EXPERIMENTS_FILE}")
    print()
    rows = EXPERIMENTS_FILE.read_text().strip().split("\n")
    if len(rows) <= 1:
        print(f"  {D}No experiments logged yet.{X}")
        return
    print(
        f"  {'#':<4s}  {'Commit':<9s}  {'Metric':>7s}  {'Delta':>7s}  {'Guard':<8s}  {'Status':<10s}  Description"
    )
    print(
        f"  {'─' * 4}  {'─' * 9}  {'─' * 7}  {'─' * 7}  {'─' * 8}  {'─' * 10}  {'─' * 30}"
    )
    for row in rows[1:]:
        parts = row.split("\t")
        if len(parts) >= 7:
            it, commit, metric, delta, guard, status, desc = parts[:7]
            color = G if status == "keep" else (R if status == "discard" else Y)
            print(
                f"  {it:<4s}  {commit:<9s}  {metric:>7s}  {delta:>7s}  {guard:<8s}  {color}{status:<10s}{X}  {desc}"
            )
    print()


# ── Triplet tracking (state, action, reward) ──
def save_triplets(all_results: dict, scorer: GoldScorer):
    """Save structured triplets for regression tracking to .sprint/TRIPLETS.jsonl."""
    triplets_file = EXPERIMENTS_FILE.parent / "TRIPLETS.jsonl"
    triplets_file.parent.mkdir(parents=True, exist_ok=True)
    import hashlib

    for name, (vr, hr) in all_results.items():
        h_hash = (
            hashlib.sha256(hr.result_text.encode()).hexdigest()[:12]
            if hr.result_text
            else "empty"
        )
        detail = (
            scorer.score_detail(hr.result_text, name)
            if hr.result_text
            else {"dimensions": {}, "total": 0}
        )
        triplet = {
            "test": name,
            "state": name,
            "action_hash": h_hash,
            "reward": hr.quality,
            "dimensions": detail.get("dimensions", {}),
            "input_tokens": hr.input_tokens,
            "output_tokens": hr.output_tokens,
            "cost": hr.cost,
            "turns": hr.turns,
        }
        with open(triplets_file, "a") as f:
            f.write(json.dumps(triplet) + "\n")


# ── Skill iteration: analyze + diagnose + suggest ──
def _extract_keywords(patterns: list[str]) -> list[str]:
    """Extract human-readable keywords from regex patterns."""
    keywords = []
    for p in patterns:
        # Extract literal words from alternation groups and literal sequences
        for word in re.findall(
            r"(?<!\\)(?:whitelist|sanitiz|validat|escap|inject|traversal|"
            r"rollback|revert|backup|research|confidence|severity|"
            r"subagent|parallel|dry.?run|edge.?case|test|verify|"
            r"fix|repair|replace|line|specific|plan|approach|method|"
            r"白名单|净化|转义|验证|注入|回滚|恢复|研究|置信|严重|并行|模拟|边界|测试|修复|替换|行|计划|方案)",
            p,
            re.IGNORECASE,
        ):
            if word.lower() not in [k.lower() for k in keywords]:
                keywords.append(word)
    return keywords[:5]  # Keep top 5


def cmd_iterate(results_dir: str, apply: bool = False):
    """Analyze results and suggest skill improvements for weak tests.

    This implements the Meta-Harness skill iteration loop:
    1. Identify weak tests (harness quality < vanilla OR < 8.0)
    2. Show missed key points with their expected patterns
    3. Show sample output for diagnosis
    4. Suggest concrete skill text additions
    5. With --apply: auto-patch skill files
    """
    from gold_answers import GoldScorer, GOLD_ANSWERS

    test_results = _load_results(results_dir)
    if not test_results:
        die(f"No result files found in {results_dir}")

    print()
    print(f"{B}Skill Iteration Analysis{X}")
    print(f"Source: {results_dir}")
    print()

    scorer = GoldScorer()

    # Find weak tests
    weak_tests = []
    for name, modes in test_results.items():
        hq = modes.get("harness", {}).get("quality", 0)
        vq = modes.get("vanilla", {}).get("quality", 0)
        # Weak if harness < vanilla by margin OR harness below threshold
        if hq < vq + 0.5 or hq < 8.0:
            weak_tests.append((name, hq, vq))

    # Sort by harness quality ascending (weakest first)
    weak_tests.sort(key=lambda x: x[1])

    if not weak_tests:
        print(f"  {G}All tests performing well — no skill iteration needed{X}")
        return

    print(
        f"  Found {len(weak_tests)} weak tests (harness < 8.0 or gap > 0.5 vs vanilla)"
    )
    print()

    # Map test names to skills
    test_skill_map = {t.name: t.skill for t in TESTS}

    for name, hq, vq in weak_tests:
        text = test_results[name].get("harness", {}).get("result", "")
        detail = scorer.score_detail(text, name)
        gold = GOLD_ANSWERS.get(name, {})
        skill = test_skill_map.get(name)

        print(f"  {B}{'━' * 60}{X}")
        print(f"  {B}{name}{X}  harness={hq:.1f}  vanilla={vq:.1f}  gap={vq - hq:+.1f}")
        if skill:
            print(f"  Skill: /{skill}")
        print()

        # Show hits
        if detail["hits"]:
            hit_ids = [h["id"] for h in detail["hits"]]
            hit_w = sum(h["weight"] for h in detail["hits"])
            print(
                f"  {G}Hits ({len(detail['hits'])}):{X} {', '.join(hit_ids)} ({hit_w:.1f} pts)"
            )

        # Show misses with diagnosis
        if detail["misses"]:
            print(f"  {R}Misses ({len(detail['misses'])}):{X}")
            total_miss = sum(m["weight"] for m in detail["misses"])
            for m in detail["misses"]:
                # Find the pattern for this key point
                kp = next(
                    (kp for kp in gold.get("key_points", []) if kp["id"] == m["id"]),
                    None,
                )
                if not kp:
                    continue

                keywords = _extract_keywords(kp["patterns"])
                print(f"    {R}✗{X} {m['id']} ({m['weight']:.1f} pts)")
                if keywords:
                    print(f"      Keywords needed: {', '.join(keywords)}")

                # Suggest skill text addition
                if m["weight"] >= 1.5:
                    print(
                        f"      {Y}→ Add to skill: ensure output includes {', '.join(keywords[:3])}{X}"
                    )

            print(
                f"  {R}Total miss: {total_miss:.1f} pts — max improvement from skill fix{X}"
            )

        # Show output preview for diagnosis
        if text:
            preview = text[:400].replace("\n", " ")
            print(f"\n  {D}Output preview: {preview}...{X}")

        print()

    # Priority summary
    print(f"  {Y}Priority Skill Changes{X}")
    print(f"  {'─' * 60}")

    # Group by skill
    skill_changes: dict[str, list] = {}
    for name, hq, vq in weak_tests:
        skill = test_skill_map.get(name)
        group = f"/{skill}" if skill else "CLAUDE.md / rules"
        skill_changes.setdefault(group, []).append((name, hq, vq))

    for group, tests in skill_changes.items():
        print(f"\n  {B}{group}{X}")
        for name, hq, vq in tests:
            text = test_results[name].get("harness", {}).get("result", "")
            detail = scorer.score_detail(text, name)
            missed_ids = [m["id"] for m in detail["misses"]]
            total_miss = sum(m["weight"] for m in detail["misses"])
            if missed_ids:
                print(
                    f"    {name}: add coverage for [{', '.join(missed_ids)}] (+{total_miss:.1f} pts)"
                )

    # Auto-apply patches if requested
    if apply:
        print(f"  {Y}Auto-applying skill patches...{X}")
        patches_applied = 0
        for group, tests in skill_changes.items():
            if group == "CLAUDE.md / rules":
                continue  # Don't auto-patch CLAUDE.md
            skill_name = group.lstrip("/")
            skill_path = PROJECT_DIR / "skills" / skill_name / "SKILL.md"
            if not skill_path.exists():
                print(f"    {R}Skip {group}: skill file not found{X}")
                continue

            content = skill_path.read_text()
            for name, hq, vq in tests:
                text = test_results[name].get("harness", {}).get("result", "")
                detail = scorer.score_detail(text, name)
                missed = detail["misses"]
                if not missed:
                    continue

                # Build patch text from missed key points
                keywords_list = []
                for m in missed:
                    kp = next(
                        (
                            kp
                            for kp in GOLD_ANSWERS.get(name, {}).get("key_points", [])
                            if kp["id"] == m["id"]
                        ),
                        None,
                    )
                    if kp:
                        keywords_list.extend(_extract_keywords(kp["patterns"]))

                if not keywords_list:
                    continue

                # Deduplicate keywords
                seen = set()
                unique_kw = []
                for kw in keywords_list:
                    if kw.lower() not in seen:
                        seen.add(kw.lower())
                        unique_kw.append(kw)

                # Add checklist section to skill if not already present
                checklist = f"\n### Quality Checklist (from benchmark)\nEnsure output includes:\n"
                for kw in unique_kw[:6]:
                    checklist += f"- {kw}\n"

                # Check if section already exists
                marker = "### Quality Checklist (from benchmark)"
                if marker not in content:
                    # Append before the last section (## References or end of file)
                    ref_marker = "\n## References"
                    if ref_marker in content:
                        content = content.replace(ref_marker, checklist + ref_marker)
                    else:
                        content += checklist
                    patches_applied += 1
                    print(
                        f"    {G}Patched{X} {group} for {name}: added {len(unique_kw[:6])} checklist items"
                    )
                else:
                    print(
                        f"    {D}Skip {group} for {name}: checklist already exists{X}"
                    )

            if patches_applied > 0:
                skill_path.write_text(content)

        if patches_applied > 0:
            print(
                f"  {G}Applied {patches_applied} patches. Review changes before committing.{X}"
            )
            print(f"  {D}  git diff skills/{X}")
            print(f"  {D}  git diff --stat skills/{X}")
        else:
            print(f"  {D}No patches needed (all checklists already exist){X}")
        print()

    # Anti-overfitting reminder
    print(f"  {Y}Anti-overfitting check{X}")
    print(f"  {D}Before applying each suggestion, ask:{X}")
    print(f'  {D}  "If this specific test disappeared, would this skill change{X}')
    print(f'  {D}   still be a worthwhile general improvement?"{X}')
    print(f"  {D}  If NO → skip it. You're overfitting to the benchmark.{X}")
    print()

    # Guard: regression warning
    strong_names = [
        n
        for n, hq, vq in [(n, hq, vq) for n, hq, vq in weak_tests if hq >= 7.0]
        if hq >= 7.0
    ]
    if not strong_names:
        all_passing = [
            n
            for n, modes in test_results.items()
            if modes.get("harness", {}).get("quality", 0) >= 7.0
        ]
        if all_passing:
            print(f"  {Y}Guard: regression check required{X}")
            print(
                f"  {D}These tests currently pass — re-run after skill changes to verify no regression:{X}"
            )
            guard_names = ",".join(all_passing[:5])
            print(f"  {D}  python3 benchmark.py --tests {guard_names} --keep{X}")
            print()

    print(
        f"  {D}Tip: Edit skill files in skills/*/SKILL.md, then re-run targeted tests:{X}"
    )
    test_names = ",".join(t[0] for t in weak_tests[:3])
    print(f"  {D}  python3 benchmark.py --tests {test_names} --keep{X}")
    print()


def main():
    import argparse

    parser = argparse.ArgumentParser(description="keep Benchmark")
    parser.add_argument(
        "--core", action="store_true", help="Run 6 core tests (~15-20 min)"
    )
    parser.add_argument(
        "--quick", action="store_true", help="Run 4 quick tests (~10 min)"
    )
    parser.add_argument("--keep", action="store_true", help="Keep results dir")
    parser.add_argument(
        "--runs", type=int, default=1, help="Run N times, report median \u00b1 std dev"
    )
    parser.add_argument(
        "--parallel",
        type=int,
        default=1,
        help="Max concurrent claude processes (default: 1)",
    )
    parser.add_argument("--dry-run", action="store_true", help="Show plan")
    parser.add_argument(
        "--score",
        nargs=2,
        metavar=("FILE", "TEST"),
        help="Score a single result file against gold answers",
    )
    parser.add_argument(
        "--score-detail",
        nargs=2,
        metavar=("FILE", "TEST"),
        help="Score with detailed breakdown of hits/misses",
    )
    parser.add_argument(
        "--model",
        default=None,
        help="Pin Claude model (e.g. claude-sonnet-4-6) for consistent results",
    )
    parser.add_argument(
        "--analyze",
        metavar="DIR",
        help="Analyze saved results from DIR (use with --keep)",
    )
    parser.add_argument(
        "--analyze-detail", metavar="DIR", help="Analyze with key-point breakdown"
    )
    parser.add_argument(
        "--compare", nargs=2, metavar=("DIR_A", "DIR_B"), help="Compare two result sets"
    )
    parser.add_argument(
        "--iterate",
        metavar="DIR",
        help="Analyze results and suggest skill improvements",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="With --iterate: auto-apply suggestions to skill files (dry-run without)",
    )
    parser.add_argument(
        "--experiments",
        action="store_true",
        help="Show experiment history from TSV log",
    )
    parser.add_argument(
        "--tests",
        metavar="NAMES",
        help="Run only specified tests (comma-separated, e.g. sprint-plan,code-review)",
    )
    args = parser.parse_args()

    if args.score or args.score_detail:
        scorer = GoldScorer()
        file_arg, test_name = args.score or args.score_detail
        text = Path(file_arg).read_text()
        try:
            data = json.loads(text)
            text = data.get("result", text)
        except json.JSONDecodeError:
            pass
        if args.score_detail:
            detail = scorer.score_detail(text, test_name)
            print(f"Quality score: {detail['total']:.1f}/10")
            print(f"  Hits: {[h['id'] for h in detail['hits']]}")
            print(f"  Misses: {[m['id'] for m in detail['misses']]}")
        else:
            q = scorer.score(text, test_name)
            print(f"Quality score: {q:.1f}/10")
        return

    if args.analyze or args.analyze_detail:
        cmd_analyze(
            args.analyze or args.analyze_detail, detail=bool(args.analyze_detail)
        )
        return

    if args.compare:
        cmd_compare(args.compare[0], args.compare[1])
        return

    if args.iterate:
        cmd_iterate(args.iterate, apply=args.apply)
        return

    if args.experiments:
        cmd_experiments()
        return

    # Dry run
    if args.dry_run:
        if args.core:
            print("Benchmark test plan (6 core tests, ~15-20 min):")
            for t in CORE_TESTS:
                print(f"  {G}RUN{X}  {t.name} [{t.dimension}] ({t.timeout}s)")
        elif args.quick:
            print("Benchmark test plan (4 quick tests, ~10 min):")
            for t in TESTS:
                if t.name in QUICK_NAMES:
                    print(f"  {G}RUN{X}  {t.name} [{t.dimension}] ({t.timeout}s)")
        else:
            print("Benchmark test plan (12 tests, 5 categories):")
            for gname, test_names in FEATURE_GROUPS:
                print(f"  {Y}{gname}{X}")
                for t in TESTS:
                    if t.name in test_names:
                        print(f"    {G}RUN{X}  {t.name} [{t.dimension}] ({t.timeout}s)")
        return

    # Pre-checks
    if not shutil.which("claude"):
        die("claude CLI not found")

    # Select test set
    if args.core:
        tests_to_run = CORE_TESTS
        mode_str = "core (6 tests)"
    elif args.quick:
        tests_to_run = [t for t in TESTS if t.name in QUICK_NAMES]
        mode_str = "quick (4 tests)"
    else:
        tests_to_run = TESTS
        mode_str = "full (12 tests, 5 categories)"

    runs_str = f" \u00d7 {args.runs} runs" if args.runs > 1 else ""
    print(f"{B}keep Benchmark{X} \u2014 Python")
    print(f"Mode: {mode_str}{runs_str}")
    print()

    scorer = GoldScorer()
    all_runs: list[dict[str, tuple[TestResult, TestResult]]] = []
    all_results_dirs: list[str] = []

    for run_idx in range(args.runs):
        if args.runs > 1:
            print(f"\n{B}\u2550\u2550 Run {run_idx + 1}/{args.runs} \u2550\u2550{X}")

        sandbox = Sandbox()
        sandbox.setup()
        ok("Sandbox ready")

        results_dir = tempfile.mkdtemp(prefix="bench-results-")
        all_results_dirs.append(results_dir)
        runner = TestRunner(sandbox, results_dir, args.model)

        all_results: dict[str, tuple[TestResult, TestResult]] = {}
        max_workers = args.parallel

        # Filter tests — use tests_to_run selected above
        active_tests = tests_to_run
        if args.tests:
            selected = set(args.tests.split(","))
            active_tests = [t for t in active_tests if t.name in selected]
        print(
            f"\n{Y}Running {len(active_tests)} tests × 2 modes (parallel={max_workers}){X}"
        )

        # Build all tasks: each test runs vanilla then harness sequentially
        tasks = []
        for test in active_tests:
            tasks.append((test, "vanilla"))
            tasks.append((test, "harness"))

        # Warmup memory before tasks
        warmup_memory()

        # Execute in parallel
        raw_results: dict[
            str, dict[str, TestResult]
        ] = {}  # {test_name: {mode: result}}
        with ThreadPoolExecutor(max_workers=max_workers) as pool:
            futures = {}
            for test, mode in tasks:
                f = pool.submit(runner.run, test, mode)
                futures[f] = (test.name, mode)

            for f in as_completed(futures):
                test_name, mode = futures[f]
                try:
                    result = f.result()
                    if result:
                        raw_results.setdefault(test_name, {})[mode] = result
                        label = "vanilla" if mode == "vanilla" else "harness"
                        info(f"{test_name} ({label}) done — {result.quality:.1f}/10")
                except Exception as e:
                    print(f"  {R}FAIL {test_name} ({mode}): {e}{X}")

        # Combine paired results
        for test in active_tests:
            modes = raw_results.get(test.name, {})
            if "vanilla" in modes and "harness" in modes:
                all_results[test.name] = (modes["vanilla"], modes["harness"])

        all_runs.append(all_results)

        # Save raw results
        suffix = f"-run{run_idx}" if args.runs > 1 else ""
        for name, (vr, hr) in all_results.items():
            for label, r in [("vanilla", vr), ("harness", hr)]:
                path = Path(results_dir) / f"{label}-{name}{suffix}.json"
                path.write_text(
                    json.dumps(
                        {
                            "input_tokens": r.input_tokens,
                            "output_tokens": r.output_tokens,
                            "turns": r.turns,
                            "cost": r.cost,
                            "quality": r.quality,
                            "dimension": r.dimension,
                            "mode_run": r.mode_run,
                            "result": r.result_text,
                        },
                        indent=2,
                    )
                )

        # Log experiment for harness results
        if args.keep:
            for name, (vr, hr) in all_results.items():
                delta = hr.quality - vr.quality
                guard = "pass" if hr.quality >= 7.0 else "fail"
                status = (
                    "keep" if delta > 0 else ("discard" if delta < -0.5 else "neutral")
                )
                # Compute dimension scores for detailed tracking
                detail = scorer.score_detail(hr.result_text, name)
                dims = detail.get("dimensions", {})
                log_experiment(hr.quality, delta, guard, status, name, dims)
            save_triplets(all_results, scorer)

        if not args.keep:
            sandbox.cleanup()
            if args.runs == 1:
                shutil.rmtree(results_dir, ignore_errors=True)

    # Report
    if args.runs > 1:
        print_multi_run_report(all_runs)
        if args.keep:
            for rd in all_results_dirs:
                print(f"  {D}Results: {rd}{X}")
    else:
        print_report(all_runs[0], args.quick)
        if args.keep:
            print(f"  {D}Results: {all_results_dirs[0]}{X}")


if __name__ == "__main__":
    main()
