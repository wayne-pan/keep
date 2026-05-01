#!/usr/bin/env bash
# protect-files.sh — PreToolUse hook for Edit|Write
# Blocks modifications to sensitive/protected files.
# Exit 2 = block (Claude sees error and adjusts), Exit 0 = allow.

set -euo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

# No file path — nothing to check
[ -z "$FILE" ] && exit 0

PROTECTED=(
  ".env"
  ".env."
  ".git/"
  "package-lock.json"
  "yarn.lock"
  "pnpm-lock.yaml"
  ".pem"
  ".key"
  "secrets/"
  "credentials"
  "id_rsa"
  "id_ed25519"
  ".ssh/"
  ".gnupg/"
)

for pattern in "${PROTECTED[@]}"; do
  if [[ "$FILE" == *"$pattern"* ]]; then
    echo "BLOCKED: '$FILE' is a protected file ($pattern). If this edit is intentional, explain why." >&2
    exit 2
  fi
done

exit 0
