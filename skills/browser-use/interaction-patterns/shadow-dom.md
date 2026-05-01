# Shadow DOM

## Problem
Elements inside Shadow DOM roots are invisible to `document.querySelector`. `browser-use state` won't enumerate them. Standard CSS selectors fail.

## Strategy
1. Use `browser-use eval` with `element.shadowRoot.querySelector()` to access shadow content
2. Fall back to coordinate clicking based on bounding box calculations
3. Use `>>>` combinator if the browser supports it (Chrome does)

## Commands

### Detect shadow roots
```bash
browser-use eval "
  Array.from(document.querySelectorAll('*')).filter(el => el.shadowRoot).map(el => ({tag: el.tagName, id: el.id, class: el.className}))
"
```

### Query inside shadow root
```bash
browser-use eval "
  document.querySelector('my-widget').shadowRoot.querySelector('button').textContent
"
```

### Click shadow DOM element (JS)
```bash
browser-use eval "
  document.querySelector('my-widget').shadowRoot.querySelector('button.submit').click()
"
```

### Click shadow DOM element (coordinates)
```bash
browser-use eval "
  const el = document.querySelector('my-widget').shadowRoot.querySelector('button.submit');
  const rect = el.getBoundingClientRect();
  JSON.stringify({x: rect.x + rect.width/2, y: rect.y + rect.height/2})
"
# Then:
browser-use click <x> <y>
```

## Fallback
- If `shadowRoot` returns null (closed shadow DOM), use screenshot + coordinate clicking
- `browser-use screenshot` still renders shadow DOM content visually — use visual inspection when DOM access is blocked
