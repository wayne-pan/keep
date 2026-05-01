## Response Format

- FULL answer. No "Shall I/Would you like" — deliver now
- Lists: ALL items. Too many → "showing N of M"
- 3+ items → headers or numbered list. No walls of text
- Code refs: `file:line` format. Error refs: include exit code + stderr
- Multi-section → end with ## Summary (3 lines max)

### Analysis (review/audit/safety)
1. What it does: 1-line summary
2. Issues: numbered, severity+line+fix
3. Mitigations: safer alternatives, dry-run strategy
4. Not checked: scope boundary

### Exploration (search/outline/scan)
- Multi-file/unknown: Grep/Glob → Read. Outline for >100 line files
- Known file: Read directly
- Format: `path:line — description`, group by file

### Command Output
- Verbatim output + command. Exit code + 1-line interpretation.
