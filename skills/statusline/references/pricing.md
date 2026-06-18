# Statusline Pricing Management

Detail for `/keep:statusline:pricing`. All prices are per 1M tokens (USD).

**Canonical config file**: `~/.local/share/keep/scripts/pricing.json`
(Symlinked from `~/.claude/scripts/pricing.json` for Claude Code — single source of truth, no drift.)

## View Current Pricing

```bash
PRICING="${HOME}/.local/share/keep/scripts/pricing.json"
if [ ! -f "$PRICING" ]; then
  echo "Error: pricing file not found at $PRICING"; exit 1
fi
python3 -c "
import json, sys
data = json.load(open('$PRICING'))
print('Model pricing (per 1M tokens):')
print(f'{'Model':<12} {'Input':>8} {'Output':>8}  Provider')
print('-' * 44)
for k, v in sorted(data.get('models', {}).items()):
    if k.startswith('_'): continue
    print(f'{k:<12} \${v[\"in\"]:>6.2f}  \${v[\"out\"]:>6.2f}  {v.get(\"provider\", \"?\")}')
c = data.get('_cache', {})
print(f'\nCache multipliers: write {c.get(\"write_mult\", 1.25)}x, read {c.get(\"read_mult\", 0.1)}x')
r = data.get('_reference', {})
print(f'Reference model: {r.get(\"model\", \"sonnet\")}')
"
```

## Add / Update Model

Ask the user for model details:
- Model name (substring to match, e.g. "gpt-4o", "glm-5")
- Input price (per 1M tokens)
- Output price (per 1M tokens)
- Provider name (optional)

Then update the canonical pricing file:
1. Read `~/.local/share/keep/scripts/pricing.json`
2. Add/update the entry in `models`
3. Write back with proper formatting

Example entry:
```json
"gpt-4o": { "in": 2.5, "out": 10, "provider": "openai" }
```

## Remove Model

Remove the entry from `models` in `~/.local/share/keep/scripts/pricing.json`.

## Update Cache Multipliers

Ask the user for the cache multiplier values. Anthropic standard: write 1.25x, read 0.1x. If the provider doesn't support cache billing, set both to 0.

Update the `_cache` section in `~/.local/share/keep/scripts/pricing.json`.

## Find Model Pricing

If the user asks about pricing for a model not in the table:
1. Search the web for "[model name] API pricing per million tokens"
2. Present the findings
3. Ask if they want to add it to the pricing table
