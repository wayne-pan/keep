# Dropdowns & Select Elements

## Problem
Custom dropdown components (not native `<select>`) require clicking to open, then clicking an option. The option elements may not exist in DOM until the dropdown is opened. Native `<select>` can use `browser-use select`, but custom ones need click sequences.

## Strategy
1. Try `browser-use select` first (works for native `<select>`)
2. For custom dropdowns: click to open → wait → find option → click option
3. For searchable dropdowns (type-ahead): click → type → wait for results → click result

## Commands

### Native select
```bash
browser-use select 5 "Option Text"
# or by value:
browser-use eval "document.querySelector('select').value = 'option_value'; document.querySelector('select').dispatchEvent(new Event('change', {bubbles: true}))"
```

### Custom dropdown (click-open-click)
```bash
# 1. Click to open
browser-use click 5
# 2. Wait for options to render
browser-use wait selector "div.dropdown-item" --timeout 2000
# 3. Re-read state to find option indices
browser-use state
# 4. Click the desired option
browser-use click <option-index>
```

### Searchable dropdown (type-ahead)
```bash
# 1. Click to open and focus the search input
browser-use click 5
# 2. Type search query
browser-use type "search term"
# 3. Wait for filtered results
browser-use wait selector "div.dropdown-item" --timeout 2000
# 4. Re-read state and click result
browser-use state && browser-use click <result-index>
```

### Multi-select dropdown
```bash
# Open dropdown, then click multiple options (they toggle)
browser-use click 5 && browser-use state
browser-use click <option1-index> && browser-use click <option2-index>
```

## Fallback
- If dropdown options are outside the viewport after opening, use `browser-use scroll down` within the dropdown container
- Some custom dropdowns close on outside click — use `browser-use eval` to select directly via JS when click sequences fail
