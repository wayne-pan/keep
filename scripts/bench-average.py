#!/usr/bin/env python3
"""bench-average.py — Average results from multiple benchmark runs.

Usage:
  python3 scripts/bench-average.py /tmp/run1 /tmp/run2 /tmp/run3
"""

import json
import sys
from pathlib import Path

TESTS = [
    ("structure-scan", "token"),
    ("safety-guard", "safety"),
    ("plan-first", "planning"),
    ("error-check", "error"),
    ("verify-review", "verify"),
    ("mcp-outline", "memory"),
    ("mcp-search", "memory"),
    ("nto-rewrite", "nto"),
    ("safety-block", "safety-hook"),
    ("skill-workflow", "skill"),
    ("skill-subagent", "skill"),
]

FEATURE_GROUPS = [
    (
        "Rules & Workflow",
        [
            "structure-scan",
            "safety-guard",
            "plan-first",
            "error-check",
            "verify-review",
        ],
    ),
    ("MCP Memory", ["mcp-outline", "mcp-search"]),
    ("Hooks", ["nto-rewrite", "safety-block"]),
    ("Skills", ["skill-workflow", "skill-subagent"]),
]

PRICE_IN = 5
PRICE_OUT = 25

R = "\033[0;31m"
G = "\033[0;32m"
Y = "\033[1;33m"
C = "\033[0;36m"
B = "\033[1m"
D = "\033[2m"
X = "\033[0m"


def load_run(results_dir: str) -> dict:
    """Load all test results from a benchmark run directory."""
    data = {}
    for name, dim in TESTS:
        for mode in ["vanilla", "harness"]:
            path = Path(results_dir) / f"{mode}-{name}.json"
            if path.exists():
                key = f"{mode}-{name}"
                data[key] = json.load(open(path))
    return data


def avg(vals):
    return sum(vals) / len(vals) if vals else 0


def main():
    dirs = sys.argv[1:]
    if len(dirs) < 2:
        print("Usage: bench-average.py <dir1> <dir2> [dir3] ...")
        sys.exit(1)

    n = len(dirs)
    print(f"\n{B}Averaging {n} benchmark runs{X}")
    print(f"Dirs: {', '.join(dirs)}")
    print()

    # Load all runs
    runs = [load_run(d) for d in dirs]

    # Compute averages
    metrics = {}
    for name, dim in TESTS:
        v_in, v_out, v_cost, v_q, v_turns = [], [], [], [], []
        h_in, h_out, h_cost, h_q, h_turns = [], [], [], [], []

        for run in runs:
            vk = f"vanilla-{name}"
            hk = f"harness-{name}"
            if vk in run:
                v_in.append(run[vk].get("input_tokens", 0))
                v_out.append(run[vk].get("output_tokens", 0))
                v_cost.append(run[vk].get("cost", 0))
                v_q.append(run[vk].get("quality", 0))
                v_turns.append(run[vk].get("turns", 0))
            if hk in run:
                h_in.append(run[hk].get("input_tokens", 0))
                h_out.append(run[hk].get("output_tokens", 0))
                h_cost.append(run[hk].get("cost", 0))
                h_q.append(run[hk].get("quality", 0))
                h_turns.append(run[hk].get("turns", 0))

        metrics[name] = {
            "vi": avg(v_in),
            "vo": avg(v_out),
            "vc": avg(v_cost),
            "vq": avg(v_q),
            "vt": avg(v_turns),
            "hi": avg(h_in),
            "ho": avg(h_out),
            "hc": avg(h_cost),
            "hq": avg(h_q),
            "ht": avg(h_turns),
            "vq_std": (sum((x - avg(v_q)) ** 2 for x in v_q) / len(v_q)) ** 0.5
            if len(v_q) > 1
            else 0,
            "hq_std": (sum((x - avg(h_q)) ** 2 for x in h_q) / len(h_q)) ** 0.5
            if len(h_q) > 1
            else 0,
            "vp_count": sum(1 for q in v_q if q >= 7.0),
            "hp_count": sum(1 for q in h_q if q >= 7.0),
        }

    # Print header
    print(
        f"{B}╔══════════════════════════════════════════════════════════════════════════════╗{X}"
    )
    print(
        f"{B}║  Harness vs Vanilla — Averaged Benchmark ({n} runs)                         ║{X}"
    )
    print(
        f"{B}║  Pricing: Opus 4.6 ($5/M in, $25/M out)                                    ║{X}"
    )
    print(
        f"{B}╚══════════════════════════════════════════════════════════════════════════════╝{X}"
    )
    print()

    sep = "──────────────  ────────────────────────────────  ────────────────────────────────  ─────"

    total_vi = total_vo = total_hi = total_ho = 0
    total_vs = total_hs = 0
    total_vcost = total_hcost = 0.0
    wins = count = 0

    for gname, test_names in FEATURE_GROUPS:
        print(f"  {Y}{gname}{X}")
        print(
            f"  {'Test':<14s}  {'Vanilla (avg in/out)':<30s}  {'Harness (avg in/out)':<30s}  Q"
        )
        print(f"  {sep}")

        g_vi = g_vo = g_hi = g_ho = 0
        g_vs = g_hs = g_wins = 0
        g_vcost = g_hcost = 0.0
        g_cnt = 0

        for name in test_names:
            m = metrics[name]
            vq = m["vq"]
            hq = m["hq"]

            if hq > vq + 0.5:
                indicator = f"{G}+{X}"
                g_wins += 1
            elif hq < vq - 0.5:
                indicator = f"{R}-{X}"
            else:
                indicator = "="

            vq_str = f"{vq:.1f}±{m['vq_std']:.1f}"
            hq_str = f"{hq:.1f}±{m['hq_std']:.1f}"

            vp_rate = m["vp_count"] / n if n > 0 else 0
            hp_rate = m["hp_count"] / n if n > 0 else 0
            pass_str = f" p@{n}:{vp_rate:.0%}/{hp_rate:.0%}"

            print(
                f"  {name:<14s}  "
                f"{m['vi']:>6.0f}/{m['vo']:<6.0f}{m['vt']:>3.0f}t "
                f"${m['vc']:<7.4f} [{vq_str}]  "
                f"{m['hi']:>6.0f}/{m['ho']:<6.0f}{m['ht']:>3.0f}t "
                f"${m['hc']:<7.4f} [{hq_str}]  "
                f"{indicator}{pass_str}"
            )

            g_vi += m["vi"]
            g_vo += m["vo"]
            g_hi += m["hi"]
            g_ho += m["ho"]
            g_vs += vq
            g_hs += hq
            g_vcost += m["vc"]
            g_hcost += m["hc"]
            g_cnt += 1

        print(f"  {sep}")
        g_tv = g_vi + g_vo
        g_th = g_hi + g_ho
        g_savings = (g_tv - g_th) * 100 / g_tv if g_tv > 0 else 0
        print(
            f"  {'Subtotal':<14s}  "
            f"{g_vi:>8.0f}/{g_vo:<8.0f} ${g_vcost:<7.4f} [{g_vs:.0f}/{g_cnt * 10}]  "
            f"{g_hi:>8.0f}/{g_ho:<8.0f} ${g_hcost:<7.4f} [{g_hs:.0f}/{g_cnt * 10}]  "
            f"{g_savings:+.1f}%tok"
        )
        print()

        total_vi += g_vi
        total_vo += g_vo
        total_hi += g_hi
        total_ho += g_ho
        total_vs += g_vs
        total_hs += g_hs
        total_vcost += g_vcost
        total_hcost += g_hcost
        wins += g_wins
        count += g_cnt

    # Overall
    total_v = total_vi + total_vo
    total_h = total_hi + total_ho
    savings = (total_v - total_h) * 100 / total_v if total_v > 0 else 0
    cost_savings = (
        (total_vcost - total_hcost) * 100 / total_vcost if total_vcost > 0 else 0
    )

    print(f"{B}══ Overall ({n} runs averaged) ══{X}")
    direction = "more costly" if savings < 0 else "savings"
    print(f"  Token efficiency:   {B}Harness {savings:+.1f}% ({direction}){X}")
    print(
        f"  Cost (Opus 4.6):    Vanilla ${total_vcost:.4f} → Harness ${total_hcost:.4f} ({cost_savings:+.1f}%)"
    )
    print(f"  Quality impact:     {B}Harness wins {wins}/{count}{X} tests")
    print(
        f"                     Vanilla avg={total_vs / count:.1f} → Harness avg={total_hs / count:.1f} (delta={total_hs - total_vs:+.1f})"
    )

    if total_vcost > 0 and total_hcost > 0:
        v_eff = total_vs / total_vcost
        h_eff = total_hs / total_hcost
        print(f"  Cost-effectiveness:  Vanilla {v_eff:.1f} → Harness {h_eff:.1f} pts/$")

    # pass@k summary
    all_vp = sum(m["vp_count"] for m in metrics.values())
    all_hp = sum(m["hp_count"] for m in metrics.values())
    all_total = count * n
    print(
        f"  pass@{n}:             Vanilla {all_vp}/{all_total} | Harness {all_hp}/{all_total}"
    )
    print(
        f"  pass^{n}:            Vanilla {'✓' if all_vp == all_total else '✗'} | Harness {'✓' if all_hp == all_total else '✗'}"
    )


if __name__ == "__main__":
    main()
