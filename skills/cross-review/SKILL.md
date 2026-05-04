---
name: keep:cross-review
version: "1.0"
triggers: []
description: >
  After completing a Complex task (3+ files OR design OR >50 lines), detect other
  available agents on this machine and offer cross-agent review. Auto-triggered by
  core.md's Complex task completion flow.
---

# Cross-Agent Review

Auto-triggers after Complex task completion (per Task Classification in core.md).

## Agent Detection

```bash
detect_agents() {
  local agents=""
  [ "${CLAUDECODE:-}" = "1" ] && agents="claude-code"
  PATH="$HOME/.opencode/bin:$PATH" command -v opencode &>/dev/null && agents="$agents opencode"
  command -v codex &>/dev/null && agents="$agents codex"
  [ -z "$agents" ] && { command -v claude &>/dev/null && agents="claude-code"; }
  echo $agents
}
```

## Flow

1. **Detect**: count available agents on this machine.
2. **Single agent** → skip.
3. **Multiple agents**:
   a. `recall("cross-agent-review-preference")` — check saved preference.
   b. **No preference** → AskUserQuestion: "Task complete. Another agent available for cross-review. Want to run it?"
      - Options: "Yes, review now" / "Always review after complex tasks" / "No, skip" / "Never ask again"
   c. Save: "Always" → `remember(type="decision", title="cross-agent-review-preference", facts=["always"], concepts=["concept:overwritable"])`. "Never" → same with facts=["never"]. One-time choices → don't save.
4. **Execute review** (if chosen):

| Current | Review agent | Command |
|---------|-------------|---------|
| Claude Code | Codex | `codex review --uncommitted "Review the recent changes. Focus on correctness, security, and edge cases."` |
| Claude Code | OpenCode | `PATH="$HOME/.opencode/bin:$PATH" opencode run "Review recent git changes. Focus on correctness, security, edge cases. Output findings as numbered list."` |
| Codex/OpenCode | Claude Code | `claude -p "Review recent git changes. Focus on correctness, security, edge cases." --allowedTools "Bash(git:*:*) Read Glob Grep"` |

   Present findings to user.

## Preference Memory

Key: `cross-agent-review-preference`. Tier: overwritable. Values: `always` | `never` | (absent = ask each time).

## Guardrails

- Only trigger for Complex tasks (not trivial/standard).
- Only once per task.
- If review agent fails/times out, report gracefully — don't block.
- Don't review if the task was itself a review.
