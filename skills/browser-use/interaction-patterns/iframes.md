# Iframes

## Problem
Elements inside `<iframe>` are invisible to `browser-use state` at the top level. Clicking by index fails because the iframe content isn't enumerated.

## Strategy
1. Detect iframe presence via `browser-use eval`
2. Get iframe's bounding box for coordinate-based clicking
3. Or use `browser-use eval` to run JS inside the iframe context

## Commands

### Detect iframes
```bash
browser-use eval "Array.from(document.querySelectorAll('iframe')).map(f => ({src: f.src, bbox: f.getBoundingClientRect()}))"
```

### Click inside iframe (coordinate method)
```bash
# Get iframe position + target element position within iframe
browser-use eval "
  const iframe = document.querySelector('iframe');
  const iframeRect = iframe.getBoundingClientRect();
  const iframeDoc = iframe.contentDocument;
  const target = iframeDoc.querySelector('button.submit');
  const targetRect = target.getBoundingClientRect();
  JSON.stringify({x: iframeRect.x + targetRect.x + targetRect.width/2, y: iframeRect.y + targetRect.y + targetRect.height/2})
"
# Then click at the calculated coordinates
browser-use click <x> <y>
```

### Click inside iframe (JS method)
```bash
browser-use eval "
  document.querySelector('iframe').contentDocument.querySelector('button.submit').click()
"
```

### Cross-origin iframes
Cross-origin iframes block `contentDocument` access. Use coordinate-based clicking only:
```bash
browser-use eval "
  const rect = document.querySelector('iframe[src*=\"other-domain\"]').getBoundingClientRect();
  JSON.stringify({x: rect.x + <offset_x>, y: rect.y + <offset_y>})
"
```

## Fallback
- If coordinate clicking fails (overlays, dynamic positioning), take a screenshot and calculate manually
- For deeply nested iframes, chain `contentDocument` access or use absolute coordinates
