## Cross-Agent Review

After completing a **Complex** task (3+ files OR design OR >50 lines, per Task Classification in core.md), check for other agents and offer cross-agent review.

### Agent Detection

```bash
detect_agents() {
  local agents=""
  [ "${CLAUDECODE:-}" = "1" ] && agents="claude-code"
  # opencode lives in ~/.opencode/bin, may not be on PATH
  PATH="$HOME/.opencode/bin:$PATH" command -v opencode &>/dev/null && agents="$agents opencode"
  command -v codex &>/dev/null && agents="$agents codex"
  # If not inside any agent, check all CLIs
  [ -z "$agents" ] && { command -v claude &>/dev/null && agents="claude-code"; }
  echo $agents
}
```

### Flow (after complex task completion)

1. **Detect**: count available agents on this machine.
2. **Single agent** → skip, no prompt.
3. **Multiple agents**:
   a. `recall("cross-agent-review-preference")` — check memory for saved preference.
   b. **No preference found** → ask user via AskUserQuestion:
      - "Task complete. Another agent is available for cross-review. Want to run it?"
      - Options: "Yes, review now" / "Always review after complex tasks" / "No, skip" / "Never ask again"
   c. Save choice to memory:
      - "Always review" → `remember(type="decision", title="cross-agent-review-preference", facts=["always"], concepts=["concept:overwritable"])`
      - "Never ask again" → `remember(type="decision", title="cross-agent-review-preference", facts=["never"], concepts=["concept:overwritable"])`
      - "Yes, review now" or "No, skip" → one-time, don't save preference
4. **Execute review** (if chosen):
   - Identify the *other* agent (not the one currently running).
   - Run non-interactive review command:

| Current agent | Review agent | Command |
|---------------|-------------|---------|
| Claude Code | Codex | `codex review --uncommitted "Review the recent changes. Focus on correctness, security, and edge cases."` |
| Claude Code | OpenCode | `PATH="$HOME/.opencode/bin:$PATH" opencode run "Review the recent git changes in this project. Focus on correctness, security, and edge cases. Output findings as a numbered list."` |
| Codex | Claude Code | `claude -p "Review the recent git changes in this project. Focus on correctness, security, and edge cases." --allowedTools "Bash(git:*:*) Read Glob Grep"` |
| OpenCode | Claude Code | `claude -p "Review the recent git changes in this project. Focus on correctness, security, and edge cases." --allowedTools "Bash(git:*:*) Read Glob Grep"` |

   - Present the review findings to the user.

### Preference Memory

- Key: `cross-agent-review-preference`
- Tier: overwritable (user can change anytime)
- Values: `always` | `never` | (absent = ask each time)
- On "always" / "never": skip AskUserQuestion in future sessions, act directly.

### Guardrails

- Only trigger for Complex tasks (not trivial/standard).
- Only trigger once per task (not after every sub-step).
- If review agent fails or times out, report failure gracefully — don't block the user.
- Don't review if the task was itself a review.
