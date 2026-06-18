# Loop Spec Schema

`.loop/<name>/loop.yaml` — the declarative loop definition. Edits to the spec are how you steer the loop, not edits to the harness.

## Full Schema

```yaml
name: <name>
schedule: "0 9 * * *"            # cron; empty string = manual run only
discovery:
  source: skill                   # skill | script | mcp
  ref: "ambient"                  # skill name, script path, or mcp tool (must exist)
generator:
  model: sonnet                   # haiku | sonnet | opus
evaluator:
  model: opus                     # different from generator recommended
  tier: deep                      # quick-gate | deep | hands-on
  skepticism: high                # "assume broken until proven otherwise"
persistence:
  state_file: .loop/<name>/STATE.md
  merge_strategy: pr              # pr | direct (experimental, untested in smoke; requires [persistence] checkpoint)
budget:
  max_iterations_per_rev: 5
  daily_cap_tokens: 200000
human_checkpoint: [persistence]   # moves that pause for human
```

Also create `.loop/<name>/STATE.md` with a header block (name, created, status=dormant). Do **not** start the loop in `define`. Use `schedule` or `run` after.

## Define Interview (§09 six-item checklist)

Walk the user through these. Refuse to complete until all six answered. Suggested defaults in brackets.

1. **Discovery source** — `skill` | `script` | `mcp`. Named ref, not "look around." [`skill: ambient` (Scout) or any user-defined discovery skill]
2. **State file** — always `.loop/<name>/STATE.md`. Non-negotiable.
3. **Evaluator** — model (`haiku` | `sonnet` | `opus`), tier (`quick-gate` | `deep` | `hands-on`), skepticism (`low` | `high`). [`opus`, `deep`, `high`]
4. **Isolation** — worktree per finding. Confirm. [yes]
5. **Token cap** — `max_iterations_per_rev`, `daily_cap_tokens`. [`5`, `200000`]
6. **Human checkpoint** — which moves pause? Subset of `[discovery, handoff, verification, persistence]`. Empty allowed but flagged with the cognitive-surrender warning. [`[persistence]`]

## Validate `discovery.ref` Before Writing Spec

Refuse to write `loop.yaml` if `discovery.ref` doesn't resolve. Silent failure mode (missing skill → empty inbox → "successful" `no_findings` revolution) is unacceptable.

- `source: skill` → `Glob skills/*/SKILL.md` matches `spec.discovery.ref`.
- `source: script` → `spec.discovery.ref` is a readable file path.
- `source: mcp` → `ListMcpResourcesTool` or `ListMcpToolsTool` shows the named tool.

If absent, surface closest matches and ask the user to pick one. Do not proceed until validated.

## Resource Check (run start)

| Primitive | How to check |
|-----------|--------------|
| `Agent` | Agent tool available (always true in Claude Code) |
| `EnterWorktree` / `ExitWorktree` | tool exists in current harness |
| `CronCreate` / `CronList` | tool exists (only required if `spec.schedule` non-empty) |
| `mcp__mind__remember` / `search` | `mind` MCP server reachable |
| `discovery.ref` skill/script/tool | validated at `define` time; re-confirm here |

If a primitive is missing, surface which one and halt. Do not fall back silently — the loop's contract is "wire these primitives"; missing one is a hard stop.

## Cron Scheduling Caveat

`CronCreate` jobs fire only while the local Claude Code REPL is idle and auto-expire after 3 days. For sleep-running, point at GitHub Actions / Cloud Routines — note this in STATE.md.
