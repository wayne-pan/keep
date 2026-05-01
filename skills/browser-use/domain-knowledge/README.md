# Domain Knowledge

Site-specific interaction knowledge. Each file covers one site or service — selectors, flows, gotchas, edge cases discovered during real automation sessions.

## Purpose

When you solve a tricky interaction on a site (login flow, SPA navigation, anti-bot bypass, complex form), record it here. Future sessions can look up the site and skip the exploration phase.

## File Naming

Use the domain name: `github.com.md`, `accounts.google.com.md`, `internal-tool.company.md`.

## Template

```markdown
# <domain>

## Key Pages
- `<url pattern>` — <what this page does>

## Selectors
| Element | Selector | Notes |
|---------|----------|-------|
| <description> | `<css/xpath>` | <caveats> |

## Flows
### <flow name>
1. Step one
2. Step two (note: <gotcha>)

## Gotchas
- <issue and workaround>
```

## Usage in Sessions

When the SKILL.md triggers a browser-use session:
1. Check if a domain knowledge file exists for the target site
2. If yes, use the recorded selectors and flows directly
3. If no, explore as normal, then create a new file with what you learned
4. If existing info is outdated, update the file
