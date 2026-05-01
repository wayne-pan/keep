## Memory Protocol — Detailed Reference

For the concise version, see "Memory Protocol" section in `core.md`.

### Relation Types

| Relation | Meaning | Behavior |
|----------|---------|----------|
| `supersedes` | Replaces older | Old deprioritized |
| `contradicts` | Conflicts | Both surface together |
| `derived_from` | Concluded from | Cascade follows chain |
| `relates_to` | Topically connected | Related context |
| `in_cluster` | Same cluster | Grouped for synthesis |

### Conflict Resolution
When `contradicts` detected: higher-confidence first. If delta < 0.2, flag for human review. Resolve via `lifecycle_transition(rejected)` on loser + `rel:supersedes` on winner.
