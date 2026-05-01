#!/usr/bin/env bash
# post-bash-scan-secrets.sh — scan Bash output for leaked secrets.
# Installed as PostToolUse hook for Bash tool.
# Non-blocking: always exits 0, outputs warnings as additionalContext JSON.

set -euo pipefail
INPUT=$(cat)

OUTPUT=$(echo "$INPUT" | jq -r '.tool_output // empty' 2>/dev/null || true)
[ -z "$OUTPUT" ] && exit 0

# Skip short outputs (no room for secrets)
[ ${#OUTPUT} -lt 20 ] && exit 0

WARNINGS=()

# Bearer tokens
if echo "$OUTPUT" | grep -qiE 'Bearer [A-Za-z0-9_\-]{20,}'; then
  WARNINGS+=("Bearer token detected in output")
fi

# API key patterns (common prefixes)
if echo "$OUTPUT" | grep -qiE '(sk-|sk_live_|sk_test_|api_key|apikey)\s*[=:]\s*["\x27]?[A-Za-z0-9_\-]{16,}'; then
  WARNINGS+=("API key detected in output")
fi

# AWS keys
if echo "$OUTPUT" | grep -qiE 'AKIA[0-9A-Z]{16}'; then
  WARNINGS+=("AWS access key detected in output")
fi

# Generic secret env vars
if echo "$OUTPUT" | grep -qiE '(PASSWORD|SECRET|TOKEN|PRIVATE_KEY|AUTH|CREDENTIAL)\s*[=:]\s*["\x27]?[^\s"'\''¿]{8,}'; then
  WARNINGS+=("Secret environment variable detected in output")
fi

# URL with credentials (user:pass@host)
if echo "$OUTPUT" | grep -qiE '[a-z]+://[^:]+:[^@]+@[a-z]'; then
  WARNINGS+=("URL with embedded credentials detected in output")
fi

# Authorization header
if echo "$OUTPUT" | grep -qiE 'Authorization:\s*(Bearer|Basic|Token)'; then
  WARNINGS+=("Authorization header detected in output")
fi

# Output warnings as additionalContext if any found
if [ ${#WARNINGS[@]} -gt 0 ]; then
  MSG=$(printf '; %s' "${WARNINGS[@]}")
  MSG="[SECRETS-SCAN] WARNING:${MSG:1}"
  jq -n --arg msg "$MSG" '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUse",
      "additionalContext": $msg
    }
  }'
fi

exit 0
