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

- **safety-guard.sh**: Blocks 100+ destructive command patterns across filesystem, SQL, AWS, GCP, Azure, Aliyun, Terraform, and Kubernetes
- **protect-files.sh**: Prevents overwriting critical files
- **post-bash-scan-secrets.sh**: Detects leaked credentials in command output
- **scope-guard.sh**: Prevents writes outside project directory
- **nonce-wrap.sh**: Wraps external content to prevent prompt injection

## Response Timeline

- Acknowledgment within 48 hours
- Initial assessment within 7 days
- Fix or mitigation within 30 days for confirmed issues
