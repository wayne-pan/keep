# Dynamic Content & SPA Navigation

## Problem
Single-page apps load content dynamically. After navigation, the DOM hasn't updated yet, so `browser-use state` returns stale data. Elements appear/disappear without page reloads.

## Strategy
1. Always wait after navigation actions in SPAs
2. Use `browser-use wait` for specific elements rather than fixed delays
3. Re-run `browser-use state` after any interaction that triggers navigation

## Commands

### Wait for element after SPA navigation
```bash
browser-use click 5 && browser-use wait selector "div.results" --timeout 5000 && browser-use state
```

### Wait for text to appear
```bash
browser-use wait text "Loading complete" --timeout 10000
```

### Poll for dynamic content
```bash
# Using eval to poll until an element appears
browser-use eval "
  new Promise((resolve, reject) => {
    const timeout = 5000;
    const start = Date.now();
    const check = () => {
      const el = document.querySelector('.dynamic-content');
      if (el) resolve(el.textContent);
      else if (Date.now() - start > timeout) reject('timeout');
      else setTimeout(check, 200);
    };
    check();
  })
"
```

### Detect infinite scroll / lazy load
```bash
# Scroll to bottom to trigger load, then wait for new content
browser-use scroll down --amount 2000 && browser-use wait selector "div.item:last-child" --timeout 3000
```

### Verify page transition completed
```bash
# Check if URL changed and content loaded
browser-use eval "JSON.stringify({url: location.href, readyState: document.readyState, title: document.title})"
```

## Fallback
- If `wait` times out, take a screenshot to see actual page state
- For infinite scroll, repeat scroll+wait cycle until no new content loads
- Some SPAs use pushState without actual navigation — check URL in eval, not just wait for load
