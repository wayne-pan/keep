# Browser-Use Advanced Patterns

Cloud, tunnels, profiles, and recovery. Read when standard commands don't suffice.

## Cloud API

```bash
browser-use cloud connect                 # Provision cloud browser and connect
browser-use cloud connect --timeout 120 --proxy-country US  # With options
browser-use cloud login <api-key>         # Save API key (or set BROWSER_USE_API_KEY)
browser-use cloud logout                  # Remove API key
browser-use cloud v2 GET /browsers        # REST passthrough (v2 or v3)
browser-use cloud v2 POST /tasks '{"task":"...","url":"..."}'
browser-use cloud v2 poll <task-id>       # Poll task until done
browser-use cloud v2 --help               # Show API endpoints
```

`cloud connect` provisions a cloud browser, connects via CDP, and prints a live URL. `browser-use close` disconnects AND stops the cloud browser.

## Tunnels

```bash
browser-use tunnel <port>                 # Start Cloudflare tunnel (idempotent)
browser-use tunnel list                   # Show active tunnels
browser-use tunnel stop <port>            # Stop tunnel
browser-use tunnel stop --all             # Stop all tunnels
```

## Profile Management

```bash
browser-use profile list                  # List detected browsers and profiles
browser-use profile sync --all            # Sync profiles to cloud
browser-use profile update                # Download/update profile-use binary
```

## Common Workflows

### Authenticated Browsing

Use Chrome profiles for sites that need existing logins (Gmail, GitHub, internal tools):

```bash
browser-use profile list                           # Check available profiles
# Ask the user which profile to use, then:
browser-use --profile "Default" open https://github.com  # Already logged in
```

### Connecting to Existing Chrome

```bash
browser-use --connect open https://example.com     # Auto-discovers Chrome's CDP endpoint
```

Requires Chrome with remote debugging enabled. Falls back to probing ports 9222/9229.

### Exposing Local Dev Servers

```bash
browser-use tunnel 3000                            # → https://abc.trycloudflare.com
browser-use open https://abc.trycloudflare.com     # Browse the tunnel
```

## Advanced Patterns

### Python Eval Fallback

When CLI commands can't express the needed logic, use `browser-use python` for full Playwright API access:

```bash
browser-use python "
page = browser.page
result = await page.evaluate('document.querySelector(\".hidden-element\").textContent')
print(result)
"
```

### Coordinate Clicking

When element indices don't work (overlays, iframes, shadow DOM):

```bash
browser-use eval "JSON.stringify(document.querySelector('iframe').getBoundingClientRect())"
browser-use click <x> <y>
```

### Self-Healing Session Recovery

```bash
browser-use state || (browser-use close && browser-use open <last-url>)
```

## Knowledge System

Before exploring a site, check the knowledge directories for reusable patterns:

- **`domain-knowledge/`** — Site-specific interaction knowledge (selectors, flows, gotchas). Check for a matching file before starting. Create/update files after discovering non-trivial interactions.
- **`interaction-patterns/`** — Generic UI mechanics (iframes, shadow DOM, dynamic content, file uploads, dialogs, custom dropdowns). Consult when standard commands fail.

Workflow: standard commands → `interaction-patterns/` → `domain-knowledge/` → `browser-use eval`/`python` → screenshot inspection.

## Gotchas

- **Browser daemon hangs**: Background daemon can become unresponsive after prolonged use or network errors. Restart: `browser-use close` → `browser-use open <url>`; if close hangs, `pkill -f browser-use` as last resort.
- **CAPTCHA/login walls**: Automated browsers hit CAPTCHAs, SSO redirects, paywalls that cannot be solved programmatically. Detect (unexpected URL changes, missing expected elements), inform user immediately; do NOT retry or loop on blocked pages.
- **Memory leaks in long sessions**: Extended sessions accumulate DOM nodes and browser memory. Restart the browser every 20-30 commands; `browser-use close && browser-use open <url>` between major task phases.
- **Stale element indices**: After page transitions, cached indices from a previous `state` call are invalid. Always re-run `browser-use state` after any navigation action.
