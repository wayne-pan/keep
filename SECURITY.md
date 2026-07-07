# Security Policy

## Reporting Vulnerabilities

If you discover a security vulnerability in keep, please report it responsibly:

- **Email**: Open a GitHub issue with the `security` label (public repo)
- **Scope**: Vulnerabilities in hooks (safety-guard bypass), memory system (data exposure), or install script (privilege escalation)

## What We Consider Security Issues

- Bypassing `safety-guard.sh` destructive command patterns
- Secret/credential exposure through hook output
- Privilege escalation via install scripts
- SQL injection or data corruption in memory system
- Path traversal in file operations

## What We Don't Consider Security Issues

- Agent behavior that follows user instructions (by design)
- Memory observations stored locally in SQLite (user-controlled data)
- Hook patterns not matching specific commands (feature request, not vulnerability)

## Security Features

keep includes several built-in security mechanisms:

- **safety-guard.sh**: Blocks 100+ destructive command patterns across filesystem, SQL, AWS, GCP, Azure, Aliyun, Terraform, and Kubernetes. Includes file-content scan for volatile-dir files (closes the Write-then-execute bypass where Claude writes a payload to `/tmp` and runs it via `psql -f`), whitespace/backslash normalization (closes `rm   -rf` / `r\m -rf` obfuscation), and position-anchored structural detection for `(eval|exec)` with `$()`/backtick substitution and command-position `$()`/backtick (closes `$(printf rm) -rf /`, `` `rm` ``, `exec $(cmd)` style obfuscation without false-positiving on `eval`/`exec` appearing inside quoted strings). See "Known Limitations" below for residual gaps.
- **protect-files.sh**: Prevents overwriting critical files
- **post-bash-scan-secrets.sh**: Detects leaked credentials in command output
- **scope-guard.sh**: Prevents writes outside project directory
- **nonce-wrap.sh**: Wraps external content to prevent prompt injection

## Known Limitations of safety-guard.sh

safety-guard uses substring + structural pattern matching, not full shell AST parsing. The following bypass vectors are known and **accepted trade-offs** (not bugs):

| Vector | Example | Why it evades | Mitigation |
|---|---|---|---|
| Encoded payload in `-c`/heredoc arg | `bash -c "$(base64 -d <<< cm0g)"` | `$(` is in argument position, not command position (structural check requires command position); base64 content doesn't substring-match destructive patterns; runtime-decoded content is never seen by the hook | None in-hook. Manual review when Claude emits `base64 -d` (or `xxd`/`hexdump`/`od`) + `$()` together. |
| Variable-expanded destructive content | `eval "$VAR"` where `$VAR` was set to `rm -rf /` elsewhere | Variable name (not value) appears in command; hook does not track variable assignments across tool calls | None in-hook. Related defense: file-content scan scope is volatile dirs only, so `source /tmp/x.sh` that sets destructive variables is still scanned at the file level. |
| Comment/string-literal false positive in volatile-dir files | `/tmp/x.sql` containing `-- TODO: DROP TABLE old` in a comment | No SQL/shell comment-awareness — substring match fires inside comments too | Intentional conservatism on volatile-dir files (already suspicious). Repo files (migrations, deploy scripts) are exempt via volatile-dir scope. |
| Non-posix nested substitution | `psql -f <(base64 -d <(cat /tmp/x))` | Tokenizer doesn't follow nested `<(...)`; treats `<(...)` as opaque token | Out of scope; rare in Claude-generated commands. Single-level `<(...)` is partially caught via `)`-strip tokenization. |

These trade-offs exist because a full shell parser (or runtime decoder for base64/hex) would add non-trivial dependency and false-positive surface for marginal coverage gain. The hook's goal is to close the **common, low-effort** bypasses an AI assistant might emit, not to be a hardened sandbox against determined attackers.

## Response Timeline

- Acknowledgment within 48 hours
- Initial assessment within 7 days
- Fix or mitigation within 30 days for confirmed issues
