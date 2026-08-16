#!/usr/bin/env bash
# scanner.sh — keep:shield static config security audit
# AgentShield-inspired (ECC) static-rule scanner for the assistant's own config.
# Surfaces: dangerous permission grants, embedded secrets, curl|bash, exfiltration,
# reverse shells, remote/npx MCP commands, prompt-injection instructions.
#
# Usage: scanner.sh [--json] [--target DIR] [--severity critical|warn|info]
# Exit:  0 = clean (no findings at/above severity), 1 = warn findings, 2 = critical findings.

set -u

TARGET="${HOME}/.claude"
FORMAT="text"
MIN_SEV="info"

while [ $# -gt 0 ]; do
  case "$1" in
    --json) FORMAT="json"; shift ;;
    --target) TARGET="${2:?--target needs a DIR}"; shift 2 ;;
    --severity) MIN_SEV="${2:?--severity needs critical|warn|info}"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 64 ;;
  esac
done

sev_rank() { case "$1" in critical) echo 2 ;; warn) echo 1 ;; *) echo 0 ;; esac; }
MIN_RANK=$(sev_rank "$MIN_SEV")

# Config-derived strings are DATA, never instructions — strip control chars
# and field delimiters, truncate. Blocks the config → scanner-output → model
# injection channel AND finding-row corruption.
sanitize() { printf '%s' "$1" | tr -d '\n\r\t|' | head -c 100; }

# --- Rule catalog (parallel arrays; grep -E patterns) ---
# categories: hooks, skills, prompts are grep-based; settings and mcp are jq walks.
R_IDS=(
  aws-key private-key generic-token pipe-shell reverse-shell exfil exec-obfuscated env-credentials
)
R_SEV=(  critical  critical   critical     critical    critical      critical  warn         warn )
R_CAT=(  hooks     hooks      hooks        hooks       hooks         hooks     hooks        hooks )
R_PAT=(
  'AKIA[0-9A-Z]{16}|aws_secret_access_key.{0,3}=.{0,3}[A-Za-z0-9/+=_-]{16}'
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  'sk-ant-api03[A-Za-z0-9_-]{8}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xoxb-[A-Za-z0-9-]+|AIza[0-9A-Za-z_-]{35}'
  '(curl|wget)[^|]*\|[[:space:]]*(sudo )?(ba)?sh\b'
  'bash -i >&|/dev/tcp/|nc -e '
  '(curl|wget)[^|]*(--data\b|--form\b|-F\b|@[^ ]*(credentials|\.aws|\.ssh|id_rsa|\.env))'
  'base64 -d.{0,40}\|(ba)?sh'
  '(cat|curl|wget|rsync|scp)[^|]*(~/\.aws|~/\.ssh|\.aws/credentials|id_rsa|\.env)[^|]*(https?://|\||>)'
)
R_MSG=(
  'AWS credential embedded in script'
  'Private key material embedded in script'
  'API token embedded in script'
  'Remote script piped straight to shell (curl into bash)'
  'Reverse shell pattern'
  'Credential/env data sent over network'
  'Obfuscated remote execution (base64-decode into shell)'
  'Secret file referenced together with network sink'
)
R_FIX=(
  'Rotate the key; load from env or secret store'
  'Remove; use an agent/secret store'
  'Rotate the token; load from env'
  'Download, verify, then run'
  'Remove — interactive remote exec'
  'Never send credential files over a network'
  'Replace with explicit, readable commands'
  'Remove the network sink'
)
# hooks+skills rules apply to both file sets; prompts rules apply to CLAUDE.md
P_IDS=( prompt-injection prompt-exfil )
P_SEV=( warn warn )
P_PAT=(
  'ignore.{0,20}(previous|prior|all).{0,20}instructions|disregard.{0,20}(instructions|rules|system prompt)'
  'exfiltrat|send.{0,30}(credentials|secrets|environment|env vars).{0,30}(to|webhook|http)'
)
P_MSG=( 'Instruction to ignore prior instructions (injection marker)' 'Instruction to exfiltrate secrets' )
P_FIX=( 'Remove the instruction; audit where this file came from' 'Remove; audit the file source' )

# --- Findings collector: severity|category|location|rule|message|fix ---
FINDINGS=()
add() { FINDINGS+=("$1|$2|$3|$4|$5|$6"); }

# --- Category: settings.json (jq walk) ---
scan_settings() {
  local f="$TARGET/settings.json"
  [ -f "$f" ] || return 0
  # wildcard permission grants
  while IFS=$'\t' read -r tool pattern; do
    [ -n "$tool" ] || continue
    local sev="warn" id
    id="wildcard-$(echo "$tool" | tr '[:upper:]' '[:lower:]')"
    [ "$tool" = "Bash" ] && sev="critical"
    [ "$(sev_rank "$sev")" -ge "$MIN_RANK" ] && add "$sev" settings "settings.json" "$id" "Wildcard $(sanitize "$tool") allow ($(sanitize "$pattern")) — arbitrary $(sanitize "$tool") use permitted" "Replace wildcard with explicit patterns"
  done < <(jq -r '.permissions.allow[]? | objects | to_entries[] | .key as $t | .value[]? | select(. == "*" or . == "**") | "\($t)\t\(.)"' "$f" 2>/dev/null)
  # hook commands living outside the audited tree
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    case "$cmd" in
      "$TARGET"*|*CLAUDE_PROJECT_DIR*|*.claude/*) continue ;;
    esac
    [ "$(sev_rank warn)" -ge "$MIN_RANK" ] && add "warn" settings "settings.json" "external-hook-cmd" "Hook command outside audited dir: $(sanitize "$cmd")" "Move hook under $TARGET or vet the path"
  done < <(jq -r '.hooks[][]?.hooks[]?.command // empty' "$f" 2>/dev/null)
}

# --- Category: mcp servers (jq walk over .claude.json) ---
scan_mcp() {
  local f=""
  for c in "$TARGET/.claude.json" "$(dirname "$TARGET")/.claude.json"; do
    [ -f "$c" ] && f="$c" && break
  done
  [ -n "$f" ] || return 0
  # remote command URLs
  while IFS=$'\t' read -r name cmd; do
    [ -n "$cmd" ] || continue
    case "$cmd" in
      http://*|https://*)
        [ "$(sev_rank critical)" -ge "$MIN_RANK" ] && add "critical" mcp "$(basename "$f")" "mcp-remote-cmd" "MCP server '$(sanitize "$name")' runs a remote URL command: $(sanitize "$cmd")" "Prefer a local stdio command you control" ;;
    esac
  done < <(jq -r '.mcpServers | to_entries[]? | "\(.key)\t\(.value.command // "")"' "$f" 2>/dev/null)
  # npx / remote package execution
  while IFS=$'\t' read -r name cmd; do
    [ -n "$cmd" ] || continue
    [ "$(sev_rank warn)" -ge "$MIN_RANK" ] && add "warn" mcp "$(basename "$f")" "mcp-npx" "MCP server '$(sanitize "$name")' executes via npx (supply-chain exposure): $(sanitize "$cmd")" "Pin exact package@version; review publisher"
  done < <(jq -r '.mcpServers | to_entries[]? | select((.value.command // "") == "npx" or ([.value.args[]? // empty] | join(" ") | test("npx"))) | "\(.key)\t\(.value.command) \(.value.args // [] | join(" "))"' "$f" 2>/dev/null)
  # env values that look like secrets (value-pattern only — name-only matching
  # false-positives on legitimate ANTHROPIC_API_KEY-style config)
  while IFS=$'\t' read -r name key; do
    [ -n "$key" ] || continue
    [ "$(sev_rank critical)" -ge "$MIN_RANK" ] && add "critical" mcp "$(basename "$f")" "mcp-env-secret" "MCP server '$(sanitize "$name")' env '$(sanitize "$key")' contains an embedded token" "Load from a secret store, not config"
  done < <(jq -r '.mcpServers | to_entries[]? | .key as $n | (.value.env // {}) | to_entries[]? | select(.value | test("sk-ant-api03|ghp_[A-Za-z0-9]{20,}|xoxb-|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}")) | "\($n)\t\(.key)"' "$f" 2>/dev/null)
}

# --- Category: grep over hooks/, skills/, CLAUDE.md ---
grep_rule() { # id sev cat pattern msg fix fileglob root
  local id="$1" sev="$2" cat="$3" pat="$4" msg="$5" fix="$6" glob="$7" root="$8"
  [ "$(sev_rank "$sev")" -ge "$MIN_RANK" ] || return 0
  [ -d "$root" ] || return 0
  local line text file
  while IFS=: read -r file line text; do
    [ -n "$file" ] || continue
    echo "$text" | grep -q 'keep-shield-safe' && continue
    add "$sev" "$cat" "${file#"$TARGET"/}:$line" "$id" "$msg" "$fix"
  done < <(grep -rEni --include="$glob" -- "$pat" "$root" 2>/dev/null)
}

scan_greps() {
  local i
  for i in "${!R_IDS[@]}"; do
    grep_rule "${R_IDS[$i]}" "${R_SEV[$i]}" hooks "${R_PAT[$i]}" "${R_MSG[$i]}" "${R_FIX[$i]}" '*.sh' "$TARGET/hooks"
    grep_rule "${R_IDS[$i]}" "${R_SEV[$i]}" skills "${R_PAT[$i]}" "${R_MSG[$i]}" "${R_FIX[$i]}" '*.md' "$TARGET/skills"
    grep_rule "${R_IDS[$i]}" "${R_SEV[$i]}" skills "${R_PAT[$i]}" "${R_MSG[$i]}" "${R_FIX[$i]}" '*.sh' "$TARGET/skills"
  done
  for i in "${!P_IDS[@]}"; do
    grep_rule "${P_IDS[$i]}" "${P_SEV[$i]}" prompts "${P_PAT[$i]}" "${P_MSG[$i]}" "${P_FIX[$i]}" 'CLAUDE.md' "$TARGET"
  done
}

# --- Render ---
render() {
  local crit=0 warn=0 info=0 status
  local f
  for f in "${FINDINGS[@]:-}"; do
    [ -n "$f" ] || continue
    case "$(echo "$f" | cut -d'|' -f1)" in
      critical) crit=$((crit + 1)) ;; warn) warn=$((warn + 1)) ;; *) info=$((info + 1)) ;;
    esac
  done
  if [ "$crit" -gt 0 ]; then status="FAIL"; elif [ "$warn" -gt 0 ]; then status="WARN"; else status="PASS"; fi
  local total=$((crit + warn + info))
  local summary="$total findings: $crit critical, $warn warn, $info info"

  if [ "$FORMAT" = "json" ]; then
    for f in "${FINDINGS[@]:-}"; do
      [ -n "$f" ] || continue
      IFS='|' read -r sev cat loc rule msg fix <<< "$f"
      jq -cn --arg sev "$sev" --arg cat "$cat" --arg loc "$loc" --arg rule "$rule" --arg msg "$msg" --arg fix "$fix" \
        '{severity:$sev, category:$cat, location:$loc, rule:$rule, message:$msg, fix:$fix}'
    done | jq -n --arg status "$status" --arg summary "$summary" \
        '{status:$status, summary:$summary, findings:[inputs]}'
    return
  fi

  echo "[STATUS] $status"
  echo "[SUMMARY] $summary"
  echo
  if [ "$total" -gt 0 ]; then
    printf '%-9s %-9s %-34s %-20s %s\n' "SEVERITY" "CATEGORY" "LOCATION" "RULE" "MESSAGE"
    local sorted
    sorted=$(printf '%s\n' "${FINDINGS[@]}" | sort -t'|' -k1,1r)
    while IFS= read -r f; do
      IFS='|' read -r sev cat loc rule msg fix <<< "$f"
      printf '%-9s %-9s %-34s %-20s %s\n' "$(echo "$sev" | tr '[:lower:]' '[:upper:]')" "$cat" "$loc" "$rule" "$msg"
    done <<< "$sorted"
    echo
    echo "Fixes:"
    while IFS= read -r f; do
      IFS='|' read -r sev cat loc rule msg fix <<< "$f"
      echo "  $rule: $fix"
    done <<< "$sorted"
  fi
}

main() {
  [ -d "$TARGET" ] || { echo "[STATUS] ERROR"; echo "target dir not found: $TARGET"; exit 64; }
  scan_settings
  scan_mcp
  scan_greps
  render
  local rc=0 f
  for f in "${FINDINGS[@]:-}"; do
    [ -n "$f" ] || continue
    case "$(echo "$f" | cut -d'|' -f1)" in
      critical) rc=2 ;; warn) [ "$rc" -eq 0 ] && rc=1 ;;
    esac
  done
  exit "$rc"
}

main
