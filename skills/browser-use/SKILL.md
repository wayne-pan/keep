---
name: keep:browser-use
version: "1.1"
triggers: ["/keep:browser-use", "/keep:browse", "/keep:scrape", "/keep:screenshot"]
description: >
  Automates browser interactions for web testing, form filling, screenshots, and
  data extraction. TRIGGER when: (1) user needs to read/scrape web page content,
  (2) WebFetch/WebSearch/curl fail or hit rate limits, (3) user needs to navigate
  websites, interact with web pages, fill forms, take screenshots, or extract
  information. Always prefer this over curl for fetching web pages — it renders
  JS and handles auth/cookies. Do NOT trigger for: API calls (use curl/the tool SDK),
  static asset fetches, or tasks with no browser interaction needed.
allowed-tools: Bash(browser-use:*)
---

# Browser Automation with browser-use CLI

The `browser-use` command provides fast, persistent browser automation. A background daemon keeps the browser open across commands, giving ~50ms latency per call. Setup: https://github.com/browser-use/browser-use/blob/main/browser_use/skill_cli/README.md

## Prerequisites

```bash
browser-use doctor    # Verify installation
```

## Core Workflow

1. **Navigate**: `browser-use open <url>` — starts browser if needed
2. **Inspect**: `browser-use state` — returns clickable elements with indices
3. **Interact**: use indices from state (`browser-use click 5`, `browser-use input 3 "text"`)
4. **Verify**: `browser-use state` or `browser-use screenshot` to confirm
5. **Repeat**: browser stays open between commands
6. **Cleanup**: `browser-use close` when done

## Browser Modes

```bash
browser-use open <url>                         # Default: headless Chromium
browser-use --headed open <url>                # Visible window
browser-use --profile "Default" open <url>     # Real Chrome with Default profile (existing logins/cookies)
browser-use --profile "Profile 1" open <url>   # Real Chrome with named profile
browser-use --connect open <url>               # Auto-discover running Chrome via CDP
browser-use --cdp-url ws://localhost:9222/... open <url>  # Connect via CDP URL
```

`--connect`, `--cdp-url`, and `--profile` are mutually exclusive.

## Command Chaining

Commands chain with `&&`. The browser persists via the daemon, so chaining is safe and efficient.

```bash
browser-use open https://example.com && browser-use state
browser-use input 5 "user@example.com" && browser-use input 6 "password" && browser-use click 7
```

Chain when you don't need intermediate output. Run separately when you need to parse `state` to discover indices first.

## Full Command Catalog

For navigation, interactions, extraction, wait, cookies, python, session, and global options: see `references/commands.md`.

Quick reference for the most-used commands:

```bash
# State — always run first to see elements and indices
browser-use state

# Interactions (use indices from state)
browser-use click <index>
browser-use input <index> "text"
browser-use keys "Enter"

# Extraction
browser-use screenshot [path.png]
browser-use get text <index>
browser-use eval "js code"
```

## Recovery Protocol

1. First attempt: `browser-use state` (may self-heal)
2. If fails: `browser-use close && browser-use open <last-url>`
3. If close hangs: `pkill -f browser-use` then fresh open
4. If persistent: `browser-use --headed open <url>` (visible mode for diagnosis)

## Troubleshooting

- **Browser won't start?** `browser-use close` then `browser-use --headed open <url>`
- **Element not found?** `browser-use scroll down` then `browser-use state`
- **Session disconnected?** `browser-use close && browser-use open <url>` (daemon auto-restarts)
- **Daemon hangs / unresponsive?** `browser-use close` → `open`; if close hangs, `pkill -f browser-use; sleep 1; browser-use open <url>`
- **CAPTCHA / login walls?** Detect (unexpected URL change, missing elements), inform user, **do not loop** on blocked pages
- **Memory leaks in long sessions?** Restart every 20-30 commands (`browser-use close && browser-use open <url>`)
- **Stale element indices?** Re-run `browser-use state` after any navigation before clicking/typing
- **Run diagnostics:** `browser-use doctor`

## Tips

1. **Always run `state` first** to see available elements and their indices
2. **Use `--headed` for debugging** to see what the browser is doing
3. **Restart every 20-30 commands** in long workflows (memory leak mitigation)

Full detail in `references/advanced.md`.

## References

- `references/commands.md` — full command catalog (navigation, interactions, extraction, wait, cookies, python, session, global options)
- `references/advanced.md` — cloud API, tunnels, profiles, advanced patterns, gotchas, knowledge system
