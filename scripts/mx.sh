#!/bin/bash
############################################################
# mx — Model eXchange
# ---------------------------------------------------------
# Unified model switcher for Claude Code and Codex CLI
# Supports: Claude, Deepseek, GLM5.1, KIMI, Qwen, etc.
# Version: 4.0.0
# License: MIT
############################################################

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Color control for account management output
NO_COLOR=false

set_no_color() {
    if [[ "$NO_COLOR" == "true" ]]; then
        RED='' GREEN='' YELLOW='' BLUE='' NC=''
    fi
}

# Config file paths
CONFIG_FILE="$HOME/.mx_config"
ACCOUNTS_FILE="$HOME/.mx_accounts"
KEYCHAIN_SERVICE="${MX_KEYCHAIN_SERVICE:-Claude Code-credentials}"
CODEX_CONFIG="$HOME/.codex/config.toml"

# ── Codex model provider table ──
declare -A CODEX_ENDPOINTS=(
    [deepseek]="https://api.deepseek.com/v1"
    [glm]="https://open.bigmodel.cn/api/paas/v4"
    [kimi]="https://api.moonshot.cn/v1"
    [qwen]="https://dashscope.aliyuncs.com/compatible-mode/v1"
    [longcat]="https://api.longcat.chat/v1"
    [minimax]="https://api.minimax.io/v1"
    [seed]="https://ark.cn-beijing.volces.com/api/v3"
)
declare -A CODEX_MODELS=(
    [deepseek]="deepseek-chat"
    [glm]="glm-5.1"
    [kimi]="kimi-k2-thinking"
    [qwen]="qwen3-max"
    [longcat]="LongCat-Flash-Thinking"
    [minimax]="MiniMax-M2"
    [seed]="doubao-seed-code-preview-latest"
)
declare -A CODEX_ENV_KEYS=(
    [deepseek]="DEEPSEEK_API_KEY"
    [glm]="GLM_API_KEY"
    [kimi]="KIMI_API_KEY"
    [qwen]="QWEN_API_KEY"
    [longcat]="LONGCAT_API_KEY"
    [minimax]="MINIMAX_API_KEY"
    [seed]="ARK_API_KEY"
)

# Load config: environment variables take priority, config file supplements
load_config() {
    # Create config file if not exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        create_default_config
        echo -e "${YELLOW}Config created: $CONFIG_FILE${NC}" >&2
        echo -e "${YELLOW}Edit the file to add your API keys${NC}" >&2
    fi

    # Smart load: only read keys from config if env var is not set
    local temp_file=$(mktemp)
    while IFS= read -r raw || [[ -n "$raw" ]]; do
        raw=${raw%$'\r'}
        [[ "$raw" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$raw" ]] && continue
        local line="${raw%%#*}"
        line=$(echo "$line" | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [[ -z "$line" ]] && continue

        if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=(.*)$ ]]; then
            local key="${BASH_REMATCH[2]}"
            local value="${BASH_REMATCH[3]}"
            value=$(echo "$value" | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//')
            local env_value="${!key}"
            local lower_env_value=$(printf '%s' "$env_value" | tr '[:upper:]' '[:lower:]')
            local is_placeholder=false
            if [[ "$lower_env_value" == *"your"* && "$lower_env_value" == *"api"* && "$lower_env_value" == *"key"* ]]; then
                is_placeholder=true
            fi
            if [[ -n "$key" && ( -z "$env_value" || "$is_placeholder" == "true" ) ]]; then
                echo "export $key=$value" >> "$temp_file"
            fi
        fi
    done < "$CONFIG_FILE"

    if [[ -s "$temp_file" ]]; then source "$temp_file"; fi
    rm -f "$temp_file"
}

# Create default config file
create_default_config() {
    cat > "$CONFIG_FILE" << 'EOF'
# mx Config — Model eXchange
# Replace with your actual API keys
# Note: Environment variables take priority over this file

# Deepseek
DEEPSEEK_API_KEY=sk-your-deepseek-api-key

# GLM (Zhipu AI)
GLM_API_KEY=your-glm-api-key

# KIMI for Coding (Moonshot AI)
KIMI_API_KEY=your-kimi-api-key

# LongCat (Meituan)
LONGCAT_API_KEY=your-longcat-api-key

# MiniMax M2
MINIMAX_API_KEY=your-minimax-api-key

# Doubao Seed-Code (ByteDance)
ARK_API_KEY=your-ark-api-key

# Qwen (Alibaba DashScope)
QWEN_API_KEY=your-qwen-api-key

# Claude (if using API key instead of Pro subscription)
CLAUDE_API_KEY=your-claude-api-key

# LiteLLM (unified proxy — use mx set url/token/model to switch)
LITELLM_BASE_URL=your-litellm-base-url
LITELLM_TOKEN=your-litellm-token
LITELLM_MODEL=claude-sonnet

# Model ID overrides (optional)
DEEPSEEK_MODEL=deepseek-chat
DEEPSEEK_SMALL_FAST_MODEL=deepseek-chat
KIMI_MODEL=kimi-for-coding
KIMI_SMALL_FAST_MODEL=kimi-for-coding
KIMI_CN_MODEL=kimi-k2-thinking
KIMI_CN_SMALL_FAST_MODEL=kimi-k2-thinking
QWEN_MODEL=qwen3-max
QWEN_SMALL_FAST_MODEL=qwen3-next-80b-a3b-instruct
GLM_MODEL=glm-5.1
GLM_SMALL_FAST_MODEL=glm-4.5-air
CLAUDE_MODEL=claude-sonnet-4-5-20250929
CLAUDE_SMALL_FAST_MODEL=claude-sonnet-4-5-20250929
OPUS_MODEL=claude-opus-4-5-20251101
OPUS_SMALL_FAST_MODEL=claude-sonnet-4-5-20250929
HAIKU_MODEL=claude-haiku-4-5
HAIKU_SMALL_FAST_MODEL=claude-haiku-4-5
LONGCAT_MODEL=LongCat-Flash-Thinking
LONGCAT_SMALL_FAST_MODEL=LongCat-Flash-Chat
MINIMAX_MODEL=MiniMax-M2
MINIMAX_SMALL_FAST_MODEL=MiniMax-M2
SEED_MODEL=doubao-seed-code-preview-latest
SEED_SMALL_FAST_MODEL=doubao-seed-code-preview-latest

EOF
}

# Check if value is effectively set (non-empty and not placeholder)
is_effectively_set() {
    local v="$1"
    [[ -z "$v" ]] && return 1
    local lower=$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')
    [[ "$lower" == *your-*-api-key ]] && return 1
    return 0
}

# Mask token for display
mask_token() {
    local t="$1" n=${#1}
    [[ -z "$t" ]] && echo "[Not Set]" && return
    (( n <= 8 )) && echo "[Set] ****" || echo "[Set] ${t:0:4}...${t:n-4:4}"
}

mask_presence() {
    local v_val="${!1}"
    is_effectively_set "$v_val" && echo "[Set]" || echo "[Not Set]"
}

# Cross-platform epoch-to-date (macOS: date -r, Linux: date -d @)
epoch_to_date() {
    local epoch="$1"
    if date -r "$epoch" "+%Y-%m-%d %H:%M" &>/dev/null; then
        date -r "$epoch" "+%Y-%m-%d %H:%M"
    else
        date -d "@$epoch" "+%Y-%m-%d %H:%M" 2>/dev/null
    fi
}

# ============================================
# Claude Pro Account Management
# ============================================

# Read credentials from macOS Keychain
read_keychain_credentials() {
    local -a services=("$KEYCHAIN_SERVICE" "Claude Code - credentials" "Claude Code" "claude" "claude.ai")
    for svc in "${services[@]}"; do
        local credentials=$(security find-generic-password -s "$svc" -w 2>/dev/null)
        if [[ $? -eq 0 && -n "$credentials" ]]; then
            KEYCHAIN_SERVICE="$svc"
            echo "$credentials"
            return 0
        fi
    done
    return 1
}

# Write credentials to macOS Keychain
write_keychain_credentials() {
    local credentials="$1"
    security delete-generic-password -s "$KEYCHAIN_SERVICE" >/dev/null 2>&1
    security add-generic-password -a "$USER" -s "$KEYCHAIN_SERVICE" -w "$credentials" >/dev/null 2>&1
    local result=$?
    if [[ $result -eq 0 ]]; then
        echo -e "${BLUE}Credentials written to Keychain${NC}" >&2
    else
        echo -e "${RED}Failed to write credentials to Keychain (error: $result)${NC}" >&2
    fi
    return $result
}

# Initialize accounts file
init_accounts_file() {
    if [[ ! -f "$ACCOUNTS_FILE" ]]; then
        echo "{}" > "$ACCOUNTS_FILE"
        chmod 600 "$ACCOUNTS_FILE"
    fi
}

# Save current account
save_account() {
    [[ "$NO_COLOR" == "true" ]] && set_no_color
    local account_name="$1"

    if [[ -z "$account_name" ]]; then
        echo -e "${RED}Account name required${NC}" >&2
        echo -e "${YELLOW}Usage: mx save-account <name>${NC}" >&2
        return 1
    fi

    local credentials=$(read_keychain_credentials)
    if [[ -z "$credentials" ]]; then
        echo -e "${RED}No credentials found in Keychain${NC}" >&2
        echo -e "${YELLOW}Please login to Claude Code first${NC}" >&2
        return 1
    fi

    init_accounts_file
    local encoded_creds=$(echo "$credentials" | base64)

    if [[ "$(cat "$ACCOUNTS_FILE")" == "{}" || ! -s "$ACCOUNTS_FILE" ]]; then
        cat > "$ACCOUNTS_FILE" << EOF
{
  "$account_name": "$encoded_creds"
}
EOF
    elif grep -q "\"$account_name\":" "$ACCOUNTS_FILE"; then
        local tmp=$(mktemp)
        sed "s/\"$account_name\": *\"[^\"]*\"/\"$account_name\": \"$encoded_creds\"/" "$ACCOUNTS_FILE" > "$tmp"
        mv "$tmp" "$ACCOUNTS_FILE"
    else
        local temp_file=$(mktemp)
        sed '$d' "$ACCOUNTS_FILE" > "$temp_file"
        grep -q '"' "$temp_file" && echo "," >> "$temp_file"
        echo "  \"$account_name\": \"$encoded_creds\"" >> "$temp_file"
        echo "}" >> "$temp_file"
        mv "$temp_file" "$ACCOUNTS_FILE"
    fi
    chmod 600 "$ACCOUNTS_FILE"

    local subscription_type=$(echo "$credentials" | grep -o '"subscriptionType":"[^"]*"' | cut -d'"' -f4)
    echo -e "${GREEN}Account saved: $account_name${NC}"
    echo "   Subscription: ${subscription_type:-Unknown}"
}

# Switch to specified account
switch_account() {
    [[ "$NO_COLOR" == "true" ]] && set_no_color
    local account_name="$1"

    if [[ -z "$account_name" ]]; then
        echo -e "${RED}Account name required${NC}" >&2
        echo -e "${YELLOW}Usage: mx switch-account <name>${NC}" >&2
        return 1
    fi

    if [[ ! -f "$ACCOUNTS_FILE" ]]; then
        echo -e "${RED}No accounts found${NC}" >&2
        echo -e "${YELLOW}Save an account first with: mx save-account <name>${NC}" >&2
        return 1
    fi

    local encoded_creds=$(grep -o "\"$account_name\": *\"[^\"]*\"" "$ACCOUNTS_FILE" | cut -d'"' -f4)
    if [[ -z "$encoded_creds" ]]; then
        echo -e "${RED}Account not found: $account_name${NC}" >&2
        echo -e "${YELLOW}Use 'mx list-accounts' to see available accounts${NC}" >&2
        return 1
    fi

    local credentials=$(echo "$encoded_creds" | base64 -d)
    if write_keychain_credentials "$credentials"; then
        echo -e "${GREEN}Switched to account: $account_name${NC}"
        echo -e "${YELLOW}Please restart Claude Code for changes to take effect${NC}"
    else
        echo -e "${RED}Failed to switch account${NC}" >&2
        return 1
    fi
}

# List all saved accounts
list_accounts() {
    if [[ ! -f "$ACCOUNTS_FILE" ]]; then
        echo -e "${YELLOW}No accounts saved${NC}"
        echo -e "${YELLOW}Use 'mx save-account <name>' to save an account${NC}"
        return 0
    fi

    echo -e "${BLUE}Saved accounts:${NC}"
    local current_creds=$(read_keychain_credentials)

    grep --color=never -o '"[^"]*": *"[^"]*"' "$ACCOUNTS_FILE" | while IFS=': ' read -r name encoded; do
        name=$(echo "$name" | tr -d '"')
        encoded=$(echo "$encoded" | tr -d '"')
        local creds=$(echo "$encoded" | base64 -d 2>/dev/null)
        local subscription=$(echo "$creds" | grep -o '"subscriptionType":"[^"]*"' | cut -d'"' -f4)
        local expires=$(echo "$creds" | grep -o '"expiresAt":[0-9]*' | cut -d':' -f2)
        local is_current=""
        [[ "$creds" == "$current_creds" ]] && is_current=" ${GREEN}(active)${NC}"
        local expires_str=""
        [[ -n "$expires" ]] && expires_str=$(epoch_to_date $((expires / 1000)))
        echo -e "   - ${YELLOW}$name${NC} (${subscription:-Unknown}${expires_str:+, expires: $expires_str})$is_current"
    done
}

# Delete saved account
delete_account() {
    local account_name="$1"
    if [[ -z "$account_name" ]]; then
        echo -e "${RED}Account name required${NC}" >&2
        echo -e "${YELLOW}Usage: mx delete-account <name>${NC}" >&2
        return 1
    fi

    if [[ ! -f "$ACCOUNTS_FILE" ]]; then
        echo -e "${RED}No accounts found${NC}" >&2
        return 1
    fi

    if ! grep -q "\"$account_name\":" "$ACCOUNTS_FILE"; then
        echo -e "${RED}Account not found: $account_name${NC}" >&2
        return 1
    fi

    local temp_file=$(mktemp)
    grep -v "\"$account_name\":" "$ACCOUNTS_FILE" > "$temp_file"
    local temp_file2=$(mktemp)
    sed 's/,\s*}/}/g' "$temp_file" > "$temp_file2"
    mv "$temp_file2" "$ACCOUNTS_FILE"
    chmod 600 "$ACCOUNTS_FILE"
    echo -e "${GREEN}Account deleted: $account_name${NC}"
}

# Show current account info
get_current_account() {
    local credentials=$(read_keychain_credentials)
    if [[ -z "$credentials" ]]; then
        echo -e "${YELLOW}No current account${NC}"
        echo -e "${YELLOW}Please login or switch to an account${NC}"
        return 1
    fi

    local subscription=$(echo "$credentials" | grep -o '"subscriptionType":"[^"]*"' | cut -d'"' -f4)
    local expires=$(echo "$credentials" | grep -o '"expiresAt":[0-9]*' | cut -d':' -f2)
    local access_token=$(echo "$credentials" | grep -o '"accessToken":"[^"]*"' | cut -d'"' -f4)
    local expires_str=""
    [[ -n "$expires" ]] && expires_str=$(epoch_to_date $((expires / 1000)))

    local account_name="Unknown"
    if [[ -f "$ACCOUNTS_FILE" ]]; then
        while IFS=': ' read -r name encoded; do
            name=$(echo "$name" | tr -d '"')
            encoded=$(echo "$encoded" | tr -d '"')
            local saved_creds=$(echo "$encoded" | base64 -d 2>/dev/null)
            if [[ "$saved_creds" == "$credentials" ]]; then
                account_name="$name"
                break
            fi
        done < <(grep --color=never -o '"[^"]*": *"[^"]*"' "$ACCOUNTS_FILE")
    fi

    echo -e "${BLUE}Current account info:${NC}"
    echo "   Account: ${account_name}"
    echo "   Subscription: ${subscription:-Unknown}"
    [[ -n "$expires_str" ]] && echo "   Token expires: ${expires_str}"
    echo -n "   Access token: "; mask_token "$access_token"
}

# Show current status (masked)
show_status() {
    echo -e "${BLUE}Claude Code config:${NC}"
    echo "   BASE_URL: ${ANTHROPIC_BASE_URL:-'Default (Anthropic)'}"
    echo -n "   AUTH_TOKEN: "; mask_token "${ANTHROPIC_AUTH_TOKEN}"
    echo "   MODEL: ${ANTHROPIC_MODEL:-'Not Set'}"
    echo ""
    echo -e "${BLUE}Codex CLI config:${NC}"
    if [[ -f "$CODEX_CONFIG" ]]; then
        local codex_model=$(grep '^model = ' "$CODEX_CONFIG" 2>/dev/null | head -1 | sed 's/model = "\(.*\)"/\1/')
        echo "   CONFIG: $CODEX_CONFIG"
        echo "   MODEL: ${codex_model:-'Not Set'}"
    else
        echo "   CONFIG: Not configured (run: mx codex <model>)"
    fi
    echo ""
    echo -e "${BLUE}API keys status:${NC}"
    echo "   DEEPSEEK_API_KEY: $(mask_presence DEEPSEEK_API_KEY)"
    echo "   GLM_API_KEY: $(mask_presence GLM_API_KEY)"
    echo "   KIMI_API_KEY: $(mask_presence KIMI_API_KEY)"
    echo "   LONGCAT_API_KEY: $(mask_presence LONGCAT_API_KEY)"
    echo "   MINIMAX_API_KEY: $(mask_presence MINIMAX_API_KEY)"
    echo "   ARK_API_KEY: $(mask_presence ARK_API_KEY)"
    echo "   QWEN_API_KEY: $(mask_presence QWEN_API_KEY)"
    echo "   LITELLM_TOKEN: $(mask_presence LITELLM_TOKEN)"
}

# Clean environment variables
clean_env() {
    unset ANTHROPIC_BASE_URL ANTHROPIC_API_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY
    unset ANTHROPIC_MODEL API_TIMEOUT_MS CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
}

# ============================================
# Claude Code: emit export statements
# ============================================
emit_env_exports() {
    local target="$1"
    load_config || return 1

    local prelude="unset ANTHROPIC_BASE_URL ANTHROPIC_API_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_MODEL API_TIMEOUT_MS CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"

    case "$target" in
        "deepseek"|"ds")
            if ! is_effectively_set "$DEEPSEEK_API_KEY"; then
                echo -e "${RED}Please configure DEEPSEEK_API_KEY${NC}" >&2
                return 1
            fi
            echo "$prelude"
            echo "export API_TIMEOUT_MS='600000'"
            echo "export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC='1'"
            echo "export ANTHROPIC_BASE_URL='https://api.deepseek.com/anthropic'"
            echo "export ANTHROPIC_API_URL='https://api.deepseek.com/anthropic'"
            echo "if [ -z \"\${DEEPSEEK_API_KEY}\" ] && [ -f \"\$HOME/.mx_config\" ]; then . \"\$HOME/.mx_config\" >/dev/null 2>&1; fi"
            echo "export ANTHROPIC_AUTH_TOKEN=\"\${DEEPSEEK_API_KEY}\""
            echo "export ANTHROPIC_MODEL='${DEEPSEEK_MODEL:-deepseek-chat}'"
            ;;
        "kimi"|"kimi2")
            if ! is_effectively_set "$KIMI_API_KEY"; then
                echo -e "${RED}Please configure KIMI_API_KEY${NC}" >&2
                return 1
            fi
            echo "$prelude"
            echo "export API_TIMEOUT_MS='600000'"
            echo "export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC='1'"
            echo "export ANTHROPIC_BASE_URL='https://api.kimi.com/coding/'"
            echo "export ANTHROPIC_API_URL='https://api.kimi.com/coding/'"
            echo "if [ -z \"\${KIMI_API_KEY}\" ] && [ -f \"\$HOME/.mx_config\" ]; then . \"\$HOME/.mx_config\" >/dev/null 2>&1; fi"
            echo "export ANTHROPIC_AUTH_TOKEN=\"\${KIMI_API_KEY}\""
            echo "export ANTHROPIC_MODEL='${KIMI_MODEL:-kimi-for-coding}'"
            ;;
        "kimi-cn")
            if ! is_effectively_set "$KIMI_API_KEY"; then
                echo -e "${RED}Please configure KIMI_API_KEY${NC}" >&2
                return 1
            fi
            echo "$prelude"
            echo "export API_TIMEOUT_MS='600000'"
            echo "export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC='1'"
            echo "export ANTHROPIC_BASE_URL='https://api.moonshot.cn/anthropic'"
            echo "export ANTHROPIC_API_URL='https://api.moonshot.cn/anthropic'"
            echo "if [ -z \"\${KIMI_API_KEY}\" ] && [ -f \"\$HOME/.mx_config\" ]; then . \"\$HOME/.mx_config\" >/dev/null 2>&1; fi"
            echo "export ANTHROPIC_AUTH_TOKEN=\"\${KIMI_API_KEY}\""
            echo "export ANTHROPIC_MODEL='${KIMI_CN_MODEL:-kimi-k2-thinking}'"
            ;;
        "qwen")
            if ! is_effectively_set "$QWEN_API_KEY"; then
                echo -e "${RED}Please configure QWEN_API_KEY${NC}" >&2
                return 1
            fi
            echo "$prelude"
            echo "export API_TIMEOUT_MS='600000'"
            echo "export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC='1'"
            echo "export ANTHROPIC_BASE_URL='https://dashscope.aliyuncs.com/api/v2/apps/claude-code-proxy'"
            echo "export ANTHROPIC_API_URL='https://dashscope.aliyuncs.com/api/v2/apps/claude-code-proxy'"
            echo "if [ -z \"\${QWEN_API_KEY}\" ] && [ -f \"\$HOME/.mx_config\" ]; then . \"\$HOME/.mx_config\" >/dev/null 2>&1; fi"
            echo "export ANTHROPIC_AUTH_TOKEN=\"\${QWEN_API_KEY}\""
            echo "export ANTHROPIC_MODEL='${QWEN_MODEL:-qwen3-max}'"
            ;;
        "glm")
            if ! is_effectively_set "$GLM_API_KEY"; then
                echo -e "${RED}Please configure GLM_API_KEY${NC}" >&2
                return 1
            fi
            echo "$prelude"
            echo "export API_TIMEOUT_MS='600000'"
            echo "export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC='1'"
            echo "export ANTHROPIC_BASE_URL='https://open.bigmodel.cn/api/anthropic'"
            echo "export ANTHROPIC_API_URL='https://open.bigmodel.cn/api/anthropic'"
            echo "if [ -z \"\${GLM_API_KEY}\" ] && [ -f \"\$HOME/.mx_config\" ]; then . \"\$HOME/.mx_config\" >/dev/null 2>&1; fi"
            echo "export ANTHROPIC_AUTH_TOKEN=\"\${GLM_API_KEY}\""
            echo "export ANTHROPIC_MODEL='${GLM_MODEL:-glm-5.1}'"
            ;;
        "longcat"|"lc")
            [[ ! -f "$HOME/.mx_config" ]] || . "$HOME/.mx_config" >/dev/null 2>&1
            if ! is_effectively_set "$LONGCAT_API_KEY"; then
                echo -e "${RED}Please configure LONGCAT_API_KEY${NC}" >&2
                return 1
            fi
            echo "$prelude"
            echo "export API_TIMEOUT_MS='600000'"
            echo "export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC='1'"
            echo "export ANTHROPIC_BASE_URL='https://api.longcat.chat/anthropic'"
            echo "export ANTHROPIC_API_URL='https://api.longcat.chat/anthropic'"
            echo "if [ -z \"\${LONGCAT_API_KEY}\" ] && [ -f \"\$HOME/.mx_config\" ]; then . \"\$HOME/.mx_config\" >/dev/null 2>&1; fi"
            echo "export ANTHROPIC_AUTH_TOKEN=\"\${LONGCAT_API_KEY}\""
            echo "export ANTHROPIC_MODEL='${LONGCAT_MODEL:-LongCat-Flash-Thinking}'"
            ;;
        "minimax"|"mm")
            if ! is_effectively_set "$MINIMAX_API_KEY"; then
                echo -e "${RED}Please configure MINIMAX_API_KEY${NC}" >&2
                return 1
            fi
            echo "$prelude"
            echo "export API_TIMEOUT_MS='600000'"
            echo "export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC='1'"
            echo "export ANTHROPIC_BASE_URL='https://api.minimax.io/anthropic'"
            echo "export ANTHROPIC_API_URL='https://api.minimax.io/anthropic'"
            echo "if [ -z \"\${MINIMAX_API_KEY}\" ] && [ -f \"\$HOME/.mx_config\" ]; then . \"\$HOME/.mx_config\" >/dev/null 2>&1; fi"
            echo "export ANTHROPIC_AUTH_TOKEN=\"\${MINIMAX_API_KEY}\""
            echo "export ANTHROPIC_MODEL='${MINIMAX_MODEL:-MiniMax-M2}'"
            ;;
        "seed"|"doubao")
            if ! is_effectively_set "$ARK_API_KEY"; then
                echo -e "${RED}Please configure ARK_API_KEY${NC}" >&2
                return 1
            fi
            echo "$prelude"
            echo "export API_TIMEOUT_MS='3000000'"
            echo "export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC='1'"
            echo "export ANTHROPIC_BASE_URL='https://ark.cn-beijing.volces.com/api/coding'"
            echo "export ANTHROPIC_API_URL='https://ark.cn-beijing.volces.com/api/coding'"
            echo "if [ -z \"\${ARK_API_KEY}\" ] && [ -f \"\$HOME/.mx_config\" ]; then . \"\$HOME/.mx_config\" >/dev/null 2>&1; fi"
            echo "export ANTHROPIC_AUTH_TOKEN=\"\${ARK_API_KEY}\""
            echo "export ANTHROPIC_MODEL='${SEED_MODEL:-doubao-seed-code-preview-latest}'"
            ;;
        "claude"|"sonnet"|"s")
            echo "$prelude"
            echo "unset ANTHROPIC_BASE_URL ANTHROPIC_API_URL ANTHROPIC_API_KEY"
            echo "export ANTHROPIC_MODEL='${CLAUDE_MODEL:-claude-sonnet-4-5-20250929}'"
            ;;
        "opus"|"o")
            echo "$prelude"
            echo "unset ANTHROPIC_BASE_URL ANTHROPIC_API_URL ANTHROPIC_API_KEY"
            echo "export ANTHROPIC_MODEL='${OPUS_MODEL:-claude-opus-4-5-20251101}'"
            ;;
        "haiku"|"h")
            echo "$prelude"
            echo "unset ANTHROPIC_BASE_URL ANTHROPIC_API_URL ANTHROPIC_API_KEY"
            echo "export ANTHROPIC_MODEL='${HAIKU_MODEL:-claude-haiku-4-5}'"
            ;;
        "litellm")
            if ! is_effectively_set "$LITELLM_TOKEN"; then
                echo -e "${RED}Please configure LITELLM_TOKEN (mx set token <key>)${NC}" >&2
                return 1
            fi
            echo "$prelude"
            echo "export API_TIMEOUT_MS='600000'"
            echo "export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC='1'"
            echo "export ANTHROPIC_BASE_URL='${LITELLM_BASE_URL}'"
            echo "export ANTHROPIC_API_URL='${LITELLM_BASE_URL}'"
            echo "export ANTHROPIC_API_KEY='${LITELLM_TOKEN}'"
            echo "export ANTHROPIC_MODEL='${LITELLM_MODEL:-claude-sonnet}'"
            ;;
        *)
            echo "# Usage: mx claude [deepseek|kimi|kimi-cn|qwen|glm|longcat|minimax|seed|claude|opus|haiku|litellm]" >&2
            return 1
            ;;
    esac
}

# ============================================
# Codex CLI: write config.toml
# ============================================
emit_codex_config() {
    local target="$1"
    load_config || return 1

    # Resolve alias
    case "$target" in
        "ds") target="deepseek" ;;
        "lc") target="longcat" ;;
        "mm") target="minimax" ;;
        "doubao") target="seed" ;;
    esac

    local model_id="${CODEX_MODELS[$target]:-}"
    local endpoint="${CODEX_ENDPOINTS[$target]:-}"
    local env_key="${CODEX_ENV_KEYS[$target]:-}"

    if [[ -z "$model_id" ]]; then
        echo -e "${RED}Unknown Codex provider: $target${NC}" >&2
        echo -e "${YELLOW}Supported: deepseek, glm, kimi, qwen, longcat, minimax, seed${NC}" >&2
        return 1
    fi

    if ! is_effectively_set "${!env_key}"; then
        echo -e "${RED}Please configure $env_key${NC}" >&2
        return 1
    fi

    local codex_dir="$HOME/.codex"
    mkdir -p "$codex_dir"

    # Read existing TOML, preserve non-model/mcp/model_providers lines
    local preserved=""
    if [[ -f "$CODEX_CONFIG" ]]; then
        preserved=$(python3 - "$CODEX_CONFIG" << 'PYEOF'
import sys
lines = []
skip_sections = {"model", "model_instructions_file", "mcp_servers", "model_providers"}
in_skip = False
for line in sys.stdin:
    s = line.strip()
    if s.startswith("["):
        section = s.strip("[]")
        base = section.split(".")[0]
        in_skip = base in skip_sections
    if not in_skip:
        lines.append(line)
print("".join(lines).rstrip())
PYEOF
        )
    fi

    # Write new config
    cat > "$CODEX_CONFIG" << EOF
# Generated by mx — $(date +%Y-%m-%d)
model = "$model_id"
model_instructions_file = "$codex_dir/AGENTS.md"
EOF

    # Preserve existing content
    if [[ -n "$preserved" ]]; then
        echo -e "\n$preserved" >> "$CODEX_CONFIG"
    fi

    # Add model provider section
    cat >> "$CODEX_CONFIG" << EOF

[model_providers.$target]
base_url = "$endpoint"
api_key_env = "$env_key"
EOF

    echo -e "${GREEN}Codex CLI → $target ($model_id)${NC}" >&2
    echo -e "${BLUE}Config: $CODEX_CONFIG${NC}" >&2
}

# Edit config file
edit_config() {
    [[ ! -f "$CONFIG_FILE" ]] && create_default_config
    echo -e "${BLUE}Opening config file...${NC}"
    echo -e "${YELLOW}Path: $CONFIG_FILE${NC}"

    if command -v cursor >/dev/null 2>&1; then
        cursor "$CONFIG_FILE" &
    elif command -v code >/dev/null 2>&1; then
        code "$CONFIG_FILE" &
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        open "$CONFIG_FILE"
    elif command -v vim >/dev/null 2>&1; then
        vim "$CONFIG_FILE"
    elif command -v nano >/dev/null 2>&1; then
        nano "$CONFIG_FILE"
    else
        echo -e "${RED}No editor found${NC}"
        echo -e "${YELLOW}Edit manually: $CONFIG_FILE${NC}"
        return 1
    fi
}

# Set API key in config file
set_api_key() {
    local provider="$1"
    local api_key="$2"

    if [[ -z "$provider" || -z "$api_key" ]]; then
        echo -e "${RED}Usage: mx set <provider> <api_key>${NC}" >&2
        echo -e "${YELLOW}Providers: deepseek, glm, kimi, longcat, minimax, seed, qwen, claude${NC}" >&2
        return 1
    fi

    # Handle generic env var setting: mx set env KEY VALUE
    if [[ "$provider" == "env" ]]; then
        local env_key="$api_key"
        local env_value="$3"
        if [[ -z "$env_key" || -z "$env_value" ]]; then
            echo -e "${RED}Usage: mx set env <KEY> <VALUE>${NC}" >&2
            return 1
        fi
        [[ ! -f "$CONFIG_FILE" ]] && create_default_config
        if grep -q "^${env_key}=" "$CONFIG_FILE" 2>/dev/null; then
            local temp_file=$(mktemp)
            sed -E "s|^${env_key}=.*|${env_key}=${env_value}|" "$CONFIG_FILE" > "$temp_file"
            mv "$temp_file" "$CONFIG_FILE"
            echo -e "${GREEN}Updated${NC} ${env_key} in ${CONFIG_FILE}"
        else
            echo "" >> "$CONFIG_FILE"
            echo "# Added by mx set env on $(date +%Y-%m-%d)" >> "$CONFIG_FILE"
            echo "${env_key}=${env_value}" >> "$CONFIG_FILE"
            echo -e "${GREEN}Added${NC} ${env_key} to ${CONFIG_FILE}"
        fi
        return 0
    fi

    # Map provider names to env var names
    local env_var=""
    case "$provider" in
        "deepseek"|"ds") env_var="DEEPSEEK_API_KEY" ;;
        "glm"|"glm4"|"glm4.7") env_var="GLM_API_KEY" ;;
        "kimi") env_var="KIMI_API_KEY" ;;
        "longcat"|"lc") env_var="LONGCAT_API_KEY" ;;
        "minimax"|"mm") env_var="MINIMAX_API_KEY" ;;
        "seed"|"doubao") env_var="ARK_API_KEY" ;;
        "qwen") env_var="QWEN_API_KEY" ;;
        "claude") env_var="CLAUDE_API_KEY" ;;
        "token") env_var="LITELLM_TOKEN" ;;
        "url") env_var="LITELLM_BASE_URL" ;;
        "model") env_var="LITELLM_MODEL" ;;
        *)
            echo -e "${RED}Unknown provider: $provider${NC}" >&2
            echo -e "${YELLOW}Supported: deepseek, glm, kimi, longcat, minimax, seed, qwen, claude, token, url, model${NC}" >&2
            return 1
            ;;
    esac

    # Create config file if not exists
    [[ ! -f "$CONFIG_FILE" ]] && create_default_config

    # Check if the env var already exists in config
    if grep -q "^${env_var}=" "$CONFIG_FILE" 2>/dev/null; then
        # Replace existing line
        local temp_file=$(mktemp)
        sed -E "s|^${env_var}=.*|${env_var}=${api_key}|" "$CONFIG_FILE" > "$temp_file"
        mv "$temp_file" "$CONFIG_FILE"
        echo -e "${GREEN}Updated${NC} ${env_var} in ${CONFIG_FILE}"
    else
        # Append new line
        echo "" >> "$CONFIG_FILE"
        echo "# Added by mx set on $(date +%Y-%m-%d)" >> "$CONFIG_FILE"
        echo "${env_var}=${api_key}" >> "$CONFIG_FILE"
        echo -e "${GREEN}Added${NC} ${env_var} to ${CONFIG_FILE}"
    fi

    # Show masked key
    local key_len=${#api_key}
    if (( key_len <= 8 )); then
        echo -e "   ${BLUE}${env_var}${NC} = [Set] ****"
    else
        echo -e "   ${BLUE}${env_var}${NC} = [Set] ${api_key:0:4}...${api_key:key_len-4:4}"
    fi
}

# Show help
show_help() {
    echo -e "${BLUE}mx — Model eXchange v4.0.0${NC}"
    echo ""
    echo -e "${YELLOW}Usage:${NC} mx [tool] <model>"
    echo ""
    echo -e "${YELLOW}Tool selector (first arg):${NC}"
    echo "  claude             - Target Claude Code (default if omitted)"
    echo "  codex              - Target Codex CLI"
    echo ""
    echo -e "${YELLOW}Claude Code models:${NC}"
    echo "  deepseek, ds       - Deepseek"
    echo "  kimi, kimi2        - KIMI for Coding"
    echo "  kimi-cn            - KIMI CN (domestic)"
    echo "  seed, doubao       - Doubao Seed-Code"
    echo "  longcat, lc        - LongCat"
    echo "  minimax, mm        - MiniMax M2"
    echo "  qwen               - Qwen"
    echo "  glm, glm4          - GLM"
    echo "  litellm            - LiteLLM proxy"
    echo "  claude, sonnet, s  - Claude Sonnet 4.5"
    echo "  opus, o            - Claude Opus 4.5"
    echo "  haiku, h           - Claude Haiku 4.5"
    echo ""
    echo -e "${YELLOW}Codex CLI models:${NC}"
    echo "  deepseek           - deepseek-chat"
    echo "  glm                - glm-5.1"
    echo "  kimi               - kimi-k2-thinking"
    echo "  qwen               - qwen3-max"
    echo "  longcat            - LongCat-Flash-Thinking"
    echo "  minimax            - MiniMax-M2"
    echo "  seed               - doubao-seed-code"
    echo ""
    echo -e "${YELLOW}Account Management:${NC}"
    echo "  save-account <name>     - Save current Claude Pro account"
    echo "  switch-account <name>   - Switch to saved account"
    echo "  list-accounts           - List all saved accounts"
    echo "  delete-account <name>   - Delete saved account"
    echo "  current-account         - Show current account info"
    echo "  claude:account          - Switch account and use Claude Sonnet"
    echo "  opus:account            - Switch account and use Opus"
    echo "  haiku:account           - Switch account and use Haiku"
    echo ""
    echo -e "${YELLOW}Other Commands:${NC}"
    echo "  status, st         - Show current configuration"
    echo "  config, cfg        - Edit config file"
    echo "  set <provider> <key> - Set API key for a provider"
    echo "  set url <url>      - Set LiteLLM base URL"
    echo "  set token <key>    - Set LiteLLM token"
    echo "  set model <model>  - Set LiteLLM model"
    echo "  set env <KEY> <VALUE> - Set arbitrary env var in config"
    echo "  help, -h           - Show this help"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  mx glm                         # Claude Code → GLM (shorthand)"
    echo "  mx claude glm                  # Claude Code → GLM (explicit)"
    echo "  mx codex glm                   # Codex CLI → GLM"
    echo "  mx codex deepseek              # Codex CLI → Deepseek"
    echo "  eval \"\$(mx glm)\"              # Apply Claude Code config"
    echo "  mx codex glm                   # Codex writes config.toml directly"
    echo "  mx set glm sk-xxxxx            # Set GLM API key"
    echo "  mx save-account work           # Save current account as 'work'"
}

# ── All valid model names (for routing) ──
is_claude_model() {
    case "$1" in
        deepseek|ds|kimi|kimi2|kimi-cn|qwen|glm|glm4|glm4.7|longcat|lc|minimax|mm|seed|doubao|claude|sonnet|s|opus|o|haiku|h|litellm) return 0 ;;
        *) return 1 ;;
    esac
}

is_codex_model() {
    case "$1" in
        deepseek|ds|glm|kimi|qwen|longcat|lc|minimax|mm|seed|doubao) return 0 ;;
        *) return 1 ;;
    esac
}

# Main function
main() {
    load_config || return 1
    local cmd="${1:-help}"

    # Handle model:account format (Claude Pro accounts)
    if [[ "$cmd" =~ ^(claude|sonnet|opus|haiku|s|o|h):(.+)$ ]]; then
        local model_type="${BASH_REMATCH[1]}"
        local account_name="${BASH_REMATCH[2]}"
        switch_account "$account_name" >&2 || return 1
        case "$model_type" in
            "claude"|"sonnet"|"s") emit_env_exports claude ;;
            "opus"|"o") emit_env_exports opus ;;
            "haiku"|"h") emit_env_exports haiku ;;
        esac
        return $?
    fi

    # ── Tool routing ──
    case "$cmd" in
        "claude")
            # mx claude <model> — explicit Claude Code target
            shift
            local model="${1:-}"
            if [[ -z "$model" ]]; then
                emit_env_exports claude
            elif is_claude_model "$model"; then
                emit_env_exports "$model"
            else
                echo -e "${RED}Unknown Claude model: $model${NC}" >&2
                return 1
            fi
            ;;
        "codex")
            # mx codex <model> — Codex CLI target
            shift
            local model="${1:-}"
            if [[ -z "$model" ]]; then
                echo -e "${YELLOW}Usage: mx codex <model>${NC}" >&2
                echo -e "${YELLOW}Models: deepseek, glm, kimi, qwen, longcat, minimax, seed${NC}" >&2
                return 1
            fi
            emit_codex_config "$model"
            ;;

        # ── Account management (no tool prefix needed) ──
        "save-account") shift; save_account "$1" ;;
        "switch-account") shift; switch_account "$1" ;;
        "list-accounts") list_accounts ;;
        "delete-account") shift; delete_account "$1" ;;
        "current-account") get_current_account ;;

        # ── Meta commands ──
        "status"|"st") show_status ;;
        "config"|"cfg") edit_config ;;
        "set") shift; set_api_key "$1" "$2" "$3" ;;
        "help"|"-h"|"--help") show_help ;;

        # ── Default: model name without tool prefix → Claude Code ──
        *)
            if is_claude_model "$cmd"; then
                emit_env_exports "$cmd"
            else
                echo -e "${RED}Unknown command: $cmd${NC}" >&2
                show_help >&2
                return 1
            fi
            ;;
    esac
}

main "$@"
