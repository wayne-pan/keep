#!/bin/bash
# ============================================================
# install.sh — keep Deployer
# Deploys complete Claude Code stack on a fresh machine.
# Tested on Ubuntu/Debian, Arch Linux, macOS (including WSL2)
#
# Usage:
#   ./scripts/install.sh              # Full stack install
#   ./scripts/install.sh --mx         # mx only (model switcher)
#   ./scripts/install.sh --help       # Show help
#
# Optional env vars:
#   CLAUDE_VERSION    — Claude Code version (default: 2.1.77)
#   SKIP_SMOKE_TEST   — Set to "1" to skip smoke tests
#
# Post-install: configure model and API key
#   mx set <model> <api-key>    (e.g. mx set glm-5 xxx)
#   Anthropic:  export ANTHROPIC_API_KEY=xxx && claude
# ============================================================

set -euo pipefail

# ── Config ──
CLAUDE_VERSION="${CLAUDE_VERSION:-2.1.77}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCAL_BIN="$HOME/.local/bin"
CLAUDE_DIR="$HOME/.claude"

# ── Mode ──
MX_ONLY=false
ADAPTER=""

# ── Colors ──
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { printf "${CYAN}[INFO]${NC}  %s\n" "$1"; }
ok()    { printf "${GREEN}[OK]${NC}    %s\n" "$1"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$1"; }
die()   { printf "${RED}[FATAL]${NC} %s\n" "$1" >&2; exit 1; }
phase() { printf "\n${CYAN}━━━ %s ━━━${NC}\n" "$1"; }

# ── Platform detection ──
detect_platform() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)
      if [ -f /etc/arch-release ]; then echo "arch"
      elif [ -f /etc/debian_version ] || command -v apt-get &>/dev/null; then echo "ubuntu"
      elif [ -f /etc/fedora-release ]; then echo "fedora"
      else echo "linux-generic"
      fi
      ;;
    *) die "Unsupported OS: $(uname -s)" ;;
  esac
}
PLATFORM="$(detect_platform)"

# ── Args ──
ADAPTERS_DIR="$SCRIPT_DIR/adapters"
list_adapters() {
  echo "Available adapters:"
  for f in "$ADAPTERS_DIR"/*.json; do
    [ -f "$f" ] || continue
    echo "  $(basename "$f" .json)"
  done
  exit 0
}
usage() {
  cat << 'USAGE_EOF'
Usage: install.sh [OPTIONS]

Options:
  --mx             Install mx only (model switcher)
  --adapter NAME   Configure mind+codedb MCP for a specific AI tool
  --list-adapters  List available adapters
  --help           Show this help message

Without options, installs the complete keep stack:
  Claude Code, mx, mind, rules, skills, hooks, plugins, settings

Adapters:
  Configure mind+codedb MCP for other AI tools:
  claude-code, cursor, windsurf, opencode, codex, openclaw
USAGE_EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mx)             MX_ONLY=true; shift ;;
    --adapter)        shift; ADAPTER="${1:-}"; shift ;;
    --list-adapters)  list_adapters ;;
    --help)           usage ;;
    *)                die "Unknown option: $1. Use --help for usage." ;;
  esac
done

# ── Adapter mode: configure mind+codedb MCP for a specific AI tool ──

if [ -n "$ADAPTER" ]; then
  ADAPTER_FILE="$ADAPTERS_DIR/$ADAPTER.json"
  if [ ! -f "$ADAPTER_FILE" ]; then
    die "Adapter not found: $ADAPTER. Run with --list-adapters to see available adapters."
  fi
  # Codex/OpenCode need full harness deployment — defer after function definitions
  if [ "$ADAPTER" = "codex" ]; then
    CODEX_ADAPTER=true
  elif [ "$ADAPTER" = "opencode" ]; then
    OPENCODE_ADAPTER=true
  fi
  if [ "$ADAPTER" != "codex" ] && [ "$ADAPTER" != "opencode" ]; then
    MIND_SERVER="$HOME/.mind/mem/server.py"
    MIND_VENV="$HOME/.mind/venv"
    if [ ! -f "$MIND_SERVER" ]; then
      die "Mind server not found at $MIND_SERVER. Run install.sh first."
    fi

  DETECT=$(python3 -c "import json; print(json.load(open('$ADAPTER_FILE')).get('detect',''))")
  CONFIG_PATH=$(eval echo "$(python3 -c "import json; print(json.load(open('$ADAPTER_FILE')).get('config_path',''))")")
  MCP_KEY=$(python3 -c "import json; print(json.load(open('$ADAPTER_FILE')).get('mcp_key','mcpServers'))")
  CONFIG_FORMAT=$(python3 -c "import json; print(json.load(open('$ADAPTER_FILE')).get('config_format','json'))")

  MEM_PYTHON="$MIND_VENV/bin/python3"
  [ ! -x "$MEM_PYTHON" ] && MEM_PYTHON="python3"

  info "Configuring adapter: $ADAPTER"
  mkdir -p "$(dirname "$CONFIG_PATH")"
  CODEDB_BIN="$LOCAL_BIN/codedb"
  python3 - "$CONFIG_PATH" "$MCP_KEY" "$MEM_PYTHON" "$MIND_SERVER" "$CODEDB_BIN" "$ADAPTER" "$CONFIG_FORMAT" << 'PYEOF'
import json, sys, os
config_path, mcp_key, python_bin, server_path, codedb_bin, adapter_name, config_format = sys.argv[1:8]

def write_toml_mcp(config_path, mcp_key, python_bin, server_path, codedb_bin):
    """Append/merge MCP server sections into a TOML config."""
    # Read existing TOML as text, find and update [mcp_servers.*] sections
    existing = ""
    if os.path.isfile(config_path):
        with open(config_path) as f:
            existing = f.read()

    lines = []
    # Keep non-mcp_servers lines
    in_mcp = False
    for line in existing.splitlines():
        if line.strip().startswith("[mcp_servers."):
            in_mcp = True
            continue
        if line.strip().startswith("[") and in_mcp:
            in_mcp = False
        if not in_mcp:
            lines.append(line)

    content = "\n".join(lines).rstrip()

    # Append MCP server sections
    if os.path.isfile(server_path):
        content += f"\n\n[mcp_servers.mind]\n"
        content += f'type = "stdio"\n'
        content += f'command = "{python_bin}"\n'
        content += f'args = ["{server_path}"]\n'
    if os.path.isfile(codedb_bin):
        content += f"\n[mcp_servers.codedb]\n"
        content += f'command = "{codedb_bin}"\n'
        content += f'args = ["mcp"]\n'

    os.makedirs(os.path.dirname(config_path), exist_ok=True)
    with open(config_path, "w") as f:
        f.write(content + "\n")

    registered = []
    if os.path.isfile(server_path): registered.append("mind")
    if os.path.isfile(codedb_bin): registered.append("codedb")
    print(f"  Config written to {config_path} (MCP: {', '.join(registered)}) [TOML]")

def write_json_mcp(config_path, mcp_key, python_bin, server_path, codedb_bin):
    """Merge MCP servers into a JSON config."""
    try:
        with open(config_path) as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        data = {}
    servers = data.setdefault(mcp_key, {})
    if os.path.isfile(server_path):
        servers["mind"] = {
            "type": "stdio",
            "command": python_bin,
            "args": [server_path],
            "env": {}
        }
    if os.path.isfile(codedb_bin):
        servers["codedb"] = {"command": codedb_bin, "args": ["mcp"]}
    os.makedirs(os.path.dirname(config_path), exist_ok=True)
    with open(config_path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    registered = [k for k in ("mind", "codedb") if k in servers]
    print(f"  Config written to {config_path} (MCP: {', '.join(registered)}) [JSON]")

if config_format == "toml":
    write_toml_mcp(config_path, mcp_key, python_bin, server_path, codedb_bin)
else:
    write_json_mcp(config_path, mcp_key, python_bin, server_path, codedb_bin)
PYEOF
  ok "$ADAPTER adapter configured"
  info "Restart $ADAPTER to use mind+codedb."
  fi  # end generic adapter block
  [ "${CODEX_ADAPTER:-}" != "true" ] && [ "${OPENCODE_ADAPTER:-}" != "true" ] && exit 0
fi

echo ""
if [ "$MX_ONLY" = true ]; then
  printf "${CYAN}  mx — Standalone Installer${NC}\n"
else
  printf "${CYAN}  keep — Installer${NC}\n"
fi
printf "${CYAN}  Source: %s${NC}\n" "$PROJECT_DIR"
echo ""

# ── Common setup ──
mkdir -p "$LOCAL_BIN"
export PATH="$LOCAL_BIN:$PATH"

# ================================================================
# mx Installation (shared by both modes)
# ================================================================
install_mx() {
  phase "Installing mx"

  MX_PATH="$LOCAL_BIN/mx.sh"
  info "Copying mx.sh..."
  cp "$PROJECT_DIR/scripts/mx.sh" "$MX_PATH"
  chmod a+x "$MX_PATH"

  # Initialize ~/.mx_config (mx.sh auto-creates on first run)
  if [ ! -f "$HOME/.mx_config" ]; then
    bash "$MX_PATH" status &>/dev/null || true
  fi
  ok "mx + config"
}

# ── Write ~/.mx_env (shared by Claude Code, Codex, etc.) ──
configure_mx_env() {
  ENV_FILE="$HOME/.mx_env"
  info "Writing env..."

  cat > "$ENV_FILE" << 'ENVEOF'
#!/bin/bash
# Source this file: . "$HOME/.mx_env"

export PATH="$HOME/.local/bin:$PATH"
ENVEOF

  [ "$MX_ONLY" = false ] && echo 'export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1' >> "$ENV_FILE"

  cat >> "$ENV_FILE" << 'ENVEOF'

[[ -f "$HOME/.mx_config" ]] && { . "$HOME/.mx_config" >/dev/null 2>&1; while IFS='=' read -r _var _rest; do export "$_var"; done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*(_API_KEY|_MODEL)=' "$HOME/.mx_config"); }

mx() {
  local script="$HOME/.local/bin/mx.sh"
  case "$1" in
    ""|help|-h|--help|status|st|config|cfg|set|save-account|switch-account|list-accounts|delete-account|current-account|codex|opencode)
      "$script" "$@" ;;
    *) eval "$("$script" "$@")" ;;
  esac
}
ENVEOF

  [ "$MX_ONLY" = false ] && echo "alias xx='claude --dangerously-skip-permissions'" >> "$ENV_FILE"
  [ "$MX_ONLY" = false ] && echo "alias glm='mx glm; claude'" >> "$ENV_FILE"
  [ "$MX_ONLY" = false ] && echo "alias glx='mx glm; claude --dangerously-skip-permissions'" >> "$ENV_FILE"

  ok "$ENV_FILE"

  # Source env from profile
  # Add to .bashrc (interactive shells) and .profile (login shells)
  # Both are needed: .bashrc has early-return guard for non-interactive,
  # so Codex launched from login shell won't get env vars from .bashrc alone.
  for RCFILE in "$HOME/.bashrc" "$HOME/.profile"; do
    [ -f "$RCFILE" ] || continue
    if ! grep -qF '.mx_env' "$RCFILE" 2>/dev/null; then
      # Remove stale .claude/env source line if present
      sed -i '/\.claude\/env/d' "$RCFILE" 2>/dev/null || true
      echo '' >> "$RCFILE"
      echo '# mx environment (shared by Claude Code, Codex, etc.)' >> "$RCFILE"
      echo '. "$HOME/.mx_env"' >> "$RCFILE"
    fi
  done
  [ -f "$HOME/.zshrc" ] && [ -n "${ZSH_VERSION:-}" ] && ! grep -qF '.mx_env' "$HOME/.zshrc" 2>/dev/null && echo '. "$HOME/.mx_env"' >> "$HOME/.zshrc"
  source "$ENV_FILE" 2>/dev/null || true
  ok "env sourced in shell profiles"
}

# ================================================================
# mx-only mode: install and exit
# ================================================================
if [ "$MX_ONLY" = true ]; then
  install_mx
  configure_mx_env

  # Smoke test
  if [ "${SKIP_SMOKE_TEST:-}" != "1" ]; then
    echo ""
    info "=== Smoke Test ==="
    [ -f "$LOCAL_BIN/mx.sh" ] && ok "mx available" || warn "mx not found"
    [ -f "$HOME/.mx_config" ] && ok "mx config" || warn "mx config missing"
  fi

  echo ""
  printf "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}\n"
  printf "${GREEN}║              mx — Ready!                                ║${NC}\n"
  printf "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}\n"
  printf "${GREEN}║${NC}                                                          ${GREEN}║${NC}\n"
  printf "${GREEN}║${NC}  ${CYAN}mx status${NC}            Show current configuration         ${GREEN}║${NC}\n"
  printf "${GREEN}║${NC}  ${CYAN}mx set <m> <key>${NC}      Configure model + API key        ${GREEN}║${NC}\n"
  printf "${GREEN}║${NC}  ${CYAN}mx help${NC}              Show all commands                 ${GREEN}║${NC}\n"
  printf "${GREEN}║${NC}                                                          ${GREEN}║${NC}\n"
  printf "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}\n"
  echo ""
  info "Run 'source ~/.bashrc' or open a new terminal."
  exit 0
fi

# ================================================================
# Full stack install below
# ================================================================

# ================================================================
# Phase 1: System Dependencies
# ================================================================
phase "Phase 1/4: System Dependencies"
info "Platform: $PLATFORM"

install_system_deps() {
  local missing=()
  for cmd in git curl jq; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  # node/npm checked separately below
  if [ ${#missing[@]} -eq 0 ] && command -v node &>/dev/null; then
    return
  fi
  info "Installing system deps: ${missing[*]:-none} + node/npm if needed"
  case "$PLATFORM" in
    ubuntu)
      sudo apt-get update -qq
      sudo apt-get install -y -qq git curl nodejs npm jq 2>/dev/null || true
      ;;
    arch)
      sudo pacman -Sy --noconfirm --needed git curl nodejs npm jq 2>/dev/null || true
      ;;
    macos)
      if command -v brew &>/dev/null; then
        brew install git curl node jq 2>/dev/null || true
      else
        warn "No Homebrew found; skipping system deps. Install manually if needed."
      fi
      ;;
    fedora)
      sudo dnf install -y git curl nodejs npm jq 2>/dev/null || true
      ;;
    linux-generic)
      warn "Unknown Linux distro; install git curl node npm jq manually."
      ;;
  esac
}
install_system_deps
ok "System dependencies"
ok "$LOCAL_BIN created"

# ================================================================
# Phase 2: Claude Code + mx + NTO
# ================================================================
phase "Phase 2/4: Claude Code + mx + NTO"

# ── Node.js ──
if ! command -v node &>/dev/null; then
  info "Installing Node.js via nvm..."
  if [ ! -d "$HOME/.nvm" ]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
  fi
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install --lts
fi
ok "Node.js $(node -v)"

# ── Claude Code ──
info "Installing Claude Code v${CLAUDE_VERSION}..."
if ! command -v claude &>/dev/null; then
  if [ "$PLATFORM" = "ubuntu" ]; then
    sudo npm install -g "@anthropic-ai/claude-code@${CLAUDE_VERSION}"
  else
    npm install -g "@anthropic-ai/claude-code@${CLAUDE_VERSION}"
  fi
fi
ok "Claude Code"

# ── mx (Model eXchange) ──
install_mx
configure_mx_env

# ── NTO (Native Token Optimizer) ──
info "NTO: built-in command rewriter (no external binary)"
ok "NTO"

# ── codedb (Code Intelligence Server) ──
install_codedb() {
  if command -v codedb &>/dev/null; then
    ok "codedb (already installed)"
    return
  fi
  info "Installing codedb..."
  local platform version codedb_bin
  case "$(uname -s)-$(uname -m)" in
    Darwin-arm64|Darwin-aarch64) platform="darwin-arm64" ;;
    Darwin-x86_64|Darwin-amd64)  platform="darwin-x86_64" ;;
    Linux-arm64|Linux-aarch64)   platform="linux-arm64" ;;
    Linux-x86_64|Linux-amd64)    platform="linux-x86_64" ;;
    *) warn "codedb: unsupported platform"; return ;;
  esac

  # Fetch latest version
  version="$(curl -fsSL -A 'keep-installer' \
    "https://api.github.com/repos/justrach/codedb/releases/latest" 2>/dev/null \
    | grep -oE '"tag_name"\s*:\s*"v[^"]*"' \
    | cut -d'"' -f4 | sed 's/^v//')" || true

  if [ -z "$version" ]; then
    warn "codedb: could not fetch version, skipping"
    return
  fi

  codedb_bin="$LOCAL_BIN/codedb"
  local url="https://github.com/justrach/codedb/releases/download/v${version}/codedb-${platform}"
  local tmp="/tmp/codedb.tmp.$$"

  if curl -fsSL -A 'keep-installer' "$url" -o "$tmp" 2>/dev/null; then
    chmod +x "$tmp"
    mv -f "$tmp" "$codedb_bin"
    ok "codedb v${version}"
  else
    warn "codedb: download failed, skipping"
    rm -f "$tmp"
  fi
}
install_codedb

# ── Codex CLI (OpenAI) ──
install_codex_cli() {
  if command -v codex &>/dev/null; then
    ok "codex CLI (already installed)"
    return
  fi
  info "Installing Codex CLI..."
  if npm install -g "@openai/codex" 2>/dev/null; then
    ok "codex CLI"
  else
    warn "codex CLI: install failed, skipping"
  fi
}
install_codex_cli

# ── OpenCode CLI ──
install_opencode_cli() {
  export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$PATH"
  if command -v opencode &>/dev/null; then
    ok "opencode CLI (already installed)"
    return
  fi
  info "Installing OpenCode CLI..."
  # Try curl installer first (official), fallback to npm
  if curl -fsSL https://opencode.ai/install | bash 2>/dev/null; then
    ok "opencode CLI"
  elif npm install -g opencode-ai 2>/dev/null; then
    ok "opencode CLI"
  else
    warn "opencode CLI: install failed, skipping"
  fi
}
install_opencode_cli

# ── uv (Python tool runner, needed for browser-use) ──
if ! command -v uv &>/dev/null; then
  info "Installing uv..."
  curl -fsSL https://astral.sh/uv/install.sh | sh 2>/dev/null && ok "uv" || warn "uv: install failed"
  export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
else
  ok "uv (already installed)"
fi

# ── browser-use (headless browser automation) ──
if command -v browser-use &>/dev/null; then
  ok "browser-use (already installed)"
elif command -v uv &>/dev/null; then
  info "Installing browser-use via uv..."
  uv tool install browser-use 2>/dev/null && ok "browser-use" || warn "browser-use: install failed"
else
  warn "browser-use: uv not available, skipping"
fi

# ================================================================
# Phase 3: Harness Configuration
# ================================================================
phase "Phase 3/4: Stack Configuration"

mkdir -p "$CLAUDE_DIR"/{rules,skills/sprint,skills/review,hooks}

# ── CLAUDE.md ──
cp "$PROJECT_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
ok "CLAUDE.md"

# ── Rules ──
for f in "$PROJECT_DIR"/rules/*.md; do
  [ -f "$f" ] && cp "$f" "$CLAUDE_DIR/rules/$(basename "$f")"
done
ok "Rules ($(ls "$PROJECT_DIR"/rules/*.md 2>/dev/null | wc -l) files)"

# Remove stale rules from previous versions
for stale in context-compaction.md safety-tiers.md session-resume.md; do
  [ -f "$CLAUDE_DIR/rules/$stale" ] && rm "$CLAUDE_DIR/rules/$stale"
done

# ── Skills ──
for skill_dir in "$PROJECT_DIR"/skills/*/; do
  skill_name="$(basename "$skill_dir")"
  if [ -f "$skill_dir/SKILL.md" ]; then
    mkdir -p "$CLAUDE_DIR/skills/$skill_name"
    cp "$skill_dir/SKILL.md" "$CLAUDE_DIR/skills/$skill_name/SKILL.md"
    # Copy references/ for progressive disclosure
    if [ -d "$skill_dir/references" ]; then
      cp -r "$skill_dir/references" "$CLAUDE_DIR/skills/$skill_name/references"
    fi
    # Copy knowledge subdirectories (domain-knowledge, interaction-patterns)
    for subdir in domain-knowledge interaction-patterns; do
      if [ -d "$skill_dir/$subdir" ]; then
        cp -r "$skill_dir/$subdir" "$CLAUDE_DIR/skills/$skill_name/$subdir"
      fi
    done
    ok "Skill: $skill_name"
  fi
done

# ── Hooks ──
for hook in safety-guard.sh nto-rewrite.sh session-stop-guard.sh session-checkpoint.sh auto-format.sh protect-files.sh audit-log.sh todo-check.sh no-todo-commit.sh post-bash-scan-secrets.sh pre-compact-instructions.sh sync-memory-rules.sh mem-record.sh mem-session.sh env-bootstrap.sh validate-edit.sh update-code-map.sh codedb-reindex.sh pr-gate.sh review-queue-inject.sh constitutional-check.sh tool-cache.sh; do
  if [ -f "$PROJECT_DIR/hooks/$hook" ]; then
    cp "$PROJECT_DIR/hooks/$hook" "$CLAUDE_DIR/hooks/$hook"
    chmod +x "$CLAUDE_DIR/hooks/$hook"
    ok "Hook: $hook"
  else
    warn "Hook source not found: $hook"
  fi
done

if [ ! -f "$CLAUDE_DIR/hooks/nto-rewrite.sh" ]; then
  warn "nto-rewrite.sh not found in hooks/"
fi

# ── Codex CLI Harness ──
deploy_codex_harness() {
  if ! command -v codex &>/dev/null && [ ! -d "$HOME/.codex" ]; then
    info "Codex not detected, skipping harness"
    return
  fi
  info "Deploying Codex harness..."

  local CODEX_DIR="$HOME/.codex"
  mkdir -p "$CODEX_DIR/hooks"

  # 1. AGENTS.md — concatenate rules + skills into instructions
  cat "$PROJECT_DIR/CLAUDE.md" > "$CODEX_DIR/AGENTS.md"
  echo -e "\n---\n" >> "$CODEX_DIR/AGENTS.md"
  for f in "$PROJECT_DIR"/rules/*.md; do
    [ -f "$f" ] || continue
    cat "$f" >> "$CODEX_DIR/AGENTS.md"
    echo -e "\n---\n" >> "$CODEX_DIR/AGENTS.md"
  done
  # Append skills (Codex reads only AGENTS.md, so embed skill content)
  for skill_dir in "$PROJECT_DIR"/skills/*/; do
    skill_file="$skill_dir/SKILL.md"
    [ -f "$skill_file" ] || continue
    echo -e "\n## Skill: $(basename "$skill_dir")\n" >> "$CODEX_DIR/AGENTS.md"
    cat "$skill_file" >> "$CODEX_DIR/AGENTS.md"
    echo -e "\n---\n" >> "$CODEX_DIR/AGENTS.md"
  done
  ok "AGENTS.md (rules + skills)"

  # 2. hooks/ — copy keep hook scripts
  cp "$PROJECT_DIR"/hooks/*.sh "$CODEX_DIR/hooks/" 2>/dev/null
  chmod +x "$CODEX_DIR/hooks/"*.sh 2>/dev/null
  ok "Codex hooks ($(ls "$CODEX_DIR/hooks/"*.sh 2>/dev/null | wc -l) scripts)"

  # 3. config.toml — generate with MCP servers + model
  local MIND="$HOME/.mind"
  local MEM_PYTHON="$MIND/venv/bin/python3"
  [ ! -x "$MEM_PYTHON" ] && MEM_PYTHON="python3"
  cat > "$CODEX_DIR/config.toml" << TOMLEOF
# Generated by keep — $(date +%Y-%m-%d)
model = "gpt-4.1"
model_instructions_file = "$CODEX_DIR/AGENTS.md"
TOMLEOF

  # Append MCP server sections
  if [ -f "$MIND/mem/server.py" ]; then
    cat >> "$CODEX_DIR/config.toml" << TOMLEOF

[mcp_servers.mind]
type = "stdio"
command = "$MEM_PYTHON"
args = ["$MIND/mem/server.py"]
TOMLEOF
  fi
  if [ -f "$LOCAL_BIN/codedb" ]; then
    cat >> "$CODEX_DIR/config.toml" << TOMLEOF

[mcp_servers.codedb]
command = "$LOCAL_BIN/codedb"
args = ["mcp"]
TOMLEOF
  fi
  ok "config.toml (MCP: mind$( [ -f "$LOCAL_BIN/codedb" ] && echo ', codedb'))"

  # 4. hooks.json — generate hook config for Codex
  local CODEX_HOOKS_DIR="$CODEX_DIR/hooks"
  python3 - "$CODEX_DIR/hooks.json" "$CODEX_HOOKS_DIR" << 'PYEOF'
import json, sys
hooks_path, hooks_dir = sys.argv[1], sys.argv[2]
H = hooks_dir
hooks_config = {
    "PreToolUse": [
        {"matcher": "Bash", "hooks": [
            {"type": "command", "command": f"{H}/safety-guard.sh"},
            {"type": "command", "command": f"{H}/nto-rewrite.sh"},
            {"type": "command", "command": f"{H}/audit-log.sh"},
            {"type": "command", "command": f"{H}/todo-check.sh"},
            {"type": "command", "command": f"{H}/no-todo-commit.sh"},
            {"type": "command", "command": f"{H}/pr-gate.sh"},
        ]},
        {"matcher": "Edit|Write", "hooks": [
            {"type": "command", "command": f"{H}/protect-files.sh"},
        ]},
        {"matcher": "mcp__mind__smart_outline|mcp__mind__smart_search|mcp__codedb__codedb_outline", "hooks": [
            {"type": "command", "command": f"{H}/tool-cache.sh pre"},
        ]},
    ],
    "PostToolUse": [
        {"matcher": "Bash", "hooks": [
            {"type": "command", "command": f"{H}/post-bash-scan-secrets.sh"},
        ]},
        {"matcher": "Write|Edit", "hooks": [
            {"type": "command", "command": f"{H}/auto-format.sh"},
            {"type": "command", "command": f"{H}/validate-edit.sh"},
        ]},
        {"matcher": "Read", "hooks": [
            {"type": "command", "command": f"{H}/constitutional-check.sh"},
        ]},
        {"matcher": "Bash|Read|Edit|Write|Glob|Grep", "hooks": [
            {"type": "command", "command": f"{H}/mem-record.sh"},
        ]},
        {"matcher": "mcp__mind__smart_outline|mcp__mind__smart_search|mcp__codedb__codedb_outline", "hooks": [
            {"type": "command", "command": f"{H}/tool-cache.sh post"},
        ]},
    ],
    "PreCompact": [
        {"hooks": [
            {"type": "command", "command": f"{H}/pre-compact-instructions.sh"},
            {"type": "command", "command": f"{H}/review-queue-inject.sh"},
        ]},
    ],
    "Stop": [
        {"hooks": [
            {"type": "command", "command": f"{H}/session-checkpoint.sh"},
            {"type": "command", "command": f"{H}/session-stop-guard.sh"},
            {"type": "command", "command": f"{H}/sync-memory-rules.sh"},
            {"type": "command", "command": f"{H}/env-bootstrap.sh"},
            {"type": "command", "command": f"{H}/mem-session.sh"},
        ]},
    ],
}
with open(hooks_path, "w") as f:
    json.dump(hooks_config, f, indent=2)
    f.write("\n")
print(f"  hooks.json generated ({sum(len(g.get('hooks',[])) for ev in hooks_config.values() for g in ev)} hooks)")
PYEOF
  ok "hooks.json"

  ok "Codex harness deployed to $CODEX_DIR"
}

# ── OpenCode CLI Harness ──
deploy_opencode_harness() {
  # opencode installs to ~/.opencode/bin — ensure it's in PATH
  export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$PATH"
  if ! command -v opencode &>/dev/null; then
    info "OpenCode not detected, skipping harness"
    return
  fi
  info "Deploying OpenCode harness..."

  local CODEX_DIR="$HOME/.codex"
  local OPENCODE_DIR="$HOME/.config/opencode"
  mkdir -p "$OPENCODE_DIR"

  # 1. opencode.json — generate with MCP servers (no model provider selected yet)
  local MIND="$HOME/.mind"
  local MEM_PYTHON="$MIND/venv/bin/python3"
  [ ! -x "$MEM_PYTHON" ] && MEM_PYTHON="python3"

  python3 - "$OPENCODE_DIR/opencode.json" "$MEM_PYTHON" "$MIND/mem/server.py" "$LOCAL_BIN/codedb" << 'PYEOF'
import json, sys, os

config_path = sys.argv[1]
mind_python = sys.argv[2]
mind_server = sys.argv[3]
codedb_bin = sys.argv[4]

# Read existing config to preserve model/provider
try:
    with open(config_path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}

data.setdefault("$schema", "https://opencode.ai/config.json")

# MCP servers — OpenCode format: type="local", command=[array], enabled=true
mcp = data.setdefault("mcp", {})
if os.path.isfile(mind_server):
    mcp["mind"] = {
        "type": "local",
        "command": [mind_python, mind_server],
        "enabled": True
    }
if os.path.isfile(codedb_bin):
    mcp["codedb"] = {
        "type": "local",
        "command": [codedb_bin, "mcp"],
        "enabled": True
    }

# Global instructions — point at ~/.claude/rules
data["instructions"] = [
    "$HOME/.claude/CLAUDE.md",
    "$HOME/.claude/rules/*.md"
]

with open(config_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

registered = [k for k in ("mind", "codedb") if k in mcp]
print(f"  Config written to {config_path} (MCP: {', '.join(registered)})")
PYEOF
  ok "opencode.json (MCP servers)"

  # 2. No hooks — OpenCode doesn't have a hooks system
  # 3. No instructions file — OpenCode reads from instructions array in config

  ok "OpenCode harness deployed to $OPENCODE_DIR"
}

# ── Handle --adapter codex/opencode (needs functions defined above) ──
if [ "${CODEX_ADAPTER:-}" = "true" ]; then
  install_opencode_cli  # also install opencode if available
  deploy_codex_harness
  exit 0
fi
if [ "${OPENCODE_ADAPTER:-}" = "true" ]; then
  install_opencode_cli
  deploy_opencode_harness
  exit 0
fi

# ── Mind MCP server (self-contained at ~/.mind) ──
MIND_DIR="$HOME/.mind"
info "Deploying mind MCP server..."
mkdir -p "$MIND_DIR"/mem/{storage,search,tools,codeparse,dream}
cp "$PROJECT_DIR/mem/server.py" "$PROJECT_DIR/mem/__init__.py" "$MIND_DIR/mem/"
for subdir in storage search tools codeparse dream; do
  for f in "$PROJECT_DIR/mem/$subdir/"*.py; do
    [ -f "$f" ] && cp "$f" "$MIND_DIR/mem/$subdir/"
  done
done

# Python venv for mind
if ! [ -d "$MIND_DIR/venv" ] || ! "$MIND_DIR/venv/bin/python3" -c "import mcp" 2>/dev/null; then
  info "Setting up mind venv..."
  python3 -m venv "$MIND_DIR/venv" 2>/dev/null
  "$MIND_DIR/venv/bin/pip" install --quiet mcp 2>/dev/null
fi
ok "mind MCP server ($MIND_DIR)"

# ================================================================
# Phase 4: Settings + Smoke Test
# ================================================================
phase "Phase 4/4: Settings + Smoke Test"

# ── Statusline (deploy script, enable via /statusline:setup) ──
mkdir -p "$CLAUDE_DIR/scripts"
cp "$PROJECT_DIR/scripts/statusline.py" "$CLAUDE_DIR/scripts/statusline.py"
cp "$PROJECT_DIR/scripts/pricing.json" "$CLAUDE_DIR/scripts/pricing.json"
chmod +x "$CLAUDE_DIR/scripts/statusline.py"
ok "statusline + pricing (run /statusline:setup to enable)"

# ── Dashboard (show.py) ──
if [ -f "$PROJECT_DIR/scripts/show.py" ]; then
  cp "$PROJECT_DIR/scripts/show.py" "$CLAUDE_DIR/scripts/show.py"
  chmod +x "$CLAUDE_DIR/scripts/show.py"
  ok "dashboard (show.py)"
fi

# ── Code Intelligence Scripts ──
for script in callgraph.py artifacts.py; do
  if [ -f "$PROJECT_DIR/scripts/$script" ]; then
    cp "$PROJECT_DIR/scripts/$script" "$CLAUDE_DIR/scripts/$script"
    chmod +x "$CLAUDE_DIR/scripts/$script"
    ok "script: $script"
  fi
done

# ── Utility Scripts (KV store, recursion guard, token chunker, etc.) ──
mkdir -p "$CLAUDE_DIR/scripts"
for script in kv-store.sh recursion-guard.sh token-chunk.sh hash-snapshot.sh nonce-wrap.sh sprint-checkpoint.sh classify-observation.sh; do
  if [ -f "$PROJECT_DIR/scripts/$script" ]; then
    cp "$PROJECT_DIR/scripts/$script" "$CLAUDE_DIR/scripts/$script"
    chmod +x "$CLAUDE_DIR/scripts/$script"
    ok "script: $script"
  fi
done

# ── settings.json (merge, never overwrite) ──
SETTINGS="$CLAUDE_DIR/settings.json"
info "Configuring settings.json..."
python3 - "$SETTINGS" "$CLAUDE_DIR" << 'PYEOF'
import json, sys, os

settings_path, claude_dir = sys.argv[1], sys.argv[2]
H = f"{claude_dir}/hooks"

def get_defaults():
    return {
        "env": {
            "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "90",
            "DISABLE_TELEMETRY": "1",
            "DISABLE_INSTALLATION_CHECKS": "1"
        },
        "permissions": {
            "deny": [
                "Read(.env)", "Read(.env.*)", "Read(.ssh/id_rsa)",
                "Read(.ssh/id_ed25519)", "Read(.ssh/*.pem)", "Read(.gnupg/*)",
                "Read(*/auth.json)", "Read(*/credentials.json)", "Read(*/secrets/*)",
                "Read(*/.pem)", "Read(*/.key)", "Edit(.env)", "Edit(.env.*)",
                "Edit(.ssh/*)", "Edit(.gnupg/*)", "Edit(*/credentials.json)",
                "Edit(*/secrets/*)"
            ]
        },
        "hooks": {
            "PreToolUse": [
                {"matcher": "Bash", "hooks": [
                    {"type": "command", "command": f"{H}/safety-guard.sh"},
                    {"type": "command", "command": f"{H}/nto-rewrite.sh"},
                    {"type": "command", "command": f"{H}/audit-log.sh"},
                    {"type": "command", "command": f"{H}/todo-check.sh"},
                    {"type": "command", "command": f"{H}/no-todo-commit.sh"},
                    {"type": "command", "command": f"{H}/pr-gate.sh"},
                ]},
                {"matcher": "Edit|Write", "hooks": [
                    {"type": "command", "command": f"{H}/protect-files.sh"},
                ]},
                {"matcher": "mcp__mind__smart_outline|mcp__mind__smart_search|mcp__codedb__codedb_outline", "hooks": [
                    {"type": "command", "command": f"{H}/tool-cache.sh pre"},
                ]},
            ],
            "PostToolUse": [
                {"matcher": "Bash", "hooks": [
                    {"type": "command", "command": f"{H}/post-bash-scan-secrets.sh"},
                ]},
                {"matcher": "Write|Edit", "hooks": [
                    {"type": "command", "command": f"{H}/auto-format.sh"},
                    {"type": "command", "command": f"{H}/validate-edit.sh"},
                ]},
                {"matcher": "Read", "hooks": [
                    {"type": "command", "command": f"{H}/constitutional-check.sh"},
                ]},
                {"matcher": "Bash|Read|Edit|Write|Glob|Grep", "hooks": [
                    {"type": "command", "command": f"{H}/mem-record.sh"},
                ]},
                {"matcher": "mcp__mind__smart_outline|mcp__mind__smart_search|mcp__codedb__codedb_outline", "hooks": [
                    {"type": "command", "command": f"{H}/tool-cache.sh post"},
                ]},
            ],
            "PreCompact": [
                {"hooks": [
                    {"type": "command", "command": f"{H}/pre-compact-instructions.sh"},
                    {"type": "command", "command": f"{H}/review-queue-inject.sh"},
                ]},
            ],
            "Stop": [
                {"hooks": [
                    {"type": "command", "command": f"{H}/session-checkpoint.sh"},
                    {"type": "command", "command": f"{H}/session-stop-guard.sh"},
                    {"type": "command", "command": f"{H}/sync-memory-rules.sh"},
                    {"type": "command", "command": f"{H}/env-bootstrap.sh"},
                    {"type": "command", "command": f"{H}/mem-session.sh"},
                ]},
            ],
        },
        "skipWebFetchPreflight": True,
        "autoMemoryEnabled": False,
        "autoUpdaterStatus": "disabled",
        "showClearContextOnPlanAccept": True,
        "skipDangerousModePermissionPrompt": True,
        "effortLevel": "high",
        "enabledPlugins": {},
        "extraKnownMarketplaces": {},
    }

def merge_hooks(existing, defaults):
    """Merge hook events by event name + matcher, dedup by command."""
    result = dict(existing) if existing else {}
    for event, new_groups in defaults.items():
        if event not in result:
            result[event] = new_groups
            continue
        groups = list(result[event])
        for ng in new_groups:
            matcher = ng.get("matcher")
            merged = False
            for i, eg in enumerate(groups):
                if eg.get("matcher") == matcher:
                    cmds = {h["command"] for h in eg.get("hooks", [])}
                    for hook in ng.get("hooks", []):
                        if hook["command"] not in cmds:
                            groups[i] = dict(eg)
                            groups[i]["hooks"] = list(eg.get("hooks", [])) + [hook]
                            cmds.add(hook["command"])
                    merged = True
                    break
            if not merged:
                groups.append(ng)
        result[event] = groups
    return result

# Keys that are always overwritten with defaults (not merged)
FORCE_OVERWRITE = set()

def deep_merge(existing, defaults):
    """Add defaults into existing. Never overwrites except FORCE_OVERWRITE keys."""
    result = dict(existing) if existing else {}
    for key, dval in defaults.items():
        if key in FORCE_OVERWRITE:
            result[key] = dval
        elif key not in result:
            result[key] = dval
        elif isinstance(result[key], dict) and isinstance(dval, dict):
            if key == "hooks":
                result[key] = merge_hooks(result[key], dval)
            else:
                result[key] = deep_merge(result[key], dval)
        elif isinstance(result[key], list) and isinstance(dval, list):
            for item in dval:
                if item not in result[key]:
                    result[key].append(item)
        # scalars: keep existing
    return result

# Load existing or start fresh
try:
    with open(settings_path) as f:
        existing = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    existing = {}

merged = deep_merge(existing, get_defaults())

with open(settings_path, "w") as f:
    json.dump(merged, f, indent=2)
    f.write("\n")

action = "merged" if existing else "created"
print(f"  settings.json {action} ({len(merged)} top-level keys)")
PYEOF
ok "settings.json"

# ── Register MCP servers ──
CLAUDE_JSON="$HOME/.claude.json"
if command -v python3 &>/dev/null; then
  MEM_PYTHON="$MIND_DIR/venv/bin/python3"
  [ ! -x "$MEM_PYTHON" ] && MEM_PYTHON="python3"
  python3 - "$CLAUDE_JSON" "$LOCAL_BIN/codedb" "$MIND_DIR/mem/server.py" "$MEM_PYTHON" << 'PYEOF'
import json, sys, os
config_path, codedb_bin, mem_server, mem_python = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
try:
    with open(config_path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
servers = data.setdefault("mcpServers", {})
if os.path.isfile(codedb_bin):
    servers["codedb"] = {"command": codedb_bin, "args": ["mcp"]}
if os.path.isfile(mem_server):
    servers["mind"] = {
        "type": "stdio",
        "command": mem_python,
        "args": [mem_server],
        "env": {}
    }
data.setdefault("installMethod", "native")
with open(config_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
  ok "codedb MCP registered"
fi

# ── Smoke test ──
if [ "${SKIP_SMOKE_TEST:-}" != "1" ]; then
  echo ""
  info "=== Smoke Test ==="
  command -v claude &>/dev/null && ok "claude available" || warn "claude not found"
  [ -f "$CLAUDE_DIR/hooks/nto-rewrite.sh" ] && ok "nto hook" || warn "nto hook not found"
  [ -f "$LOCAL_BIN/mx.sh" ] && ok "mx available" || warn "mx not found"
  [ -f "$LOCAL_BIN/codedb" ] && ok "codedb available" || warn "codedb not found"
  command -v browser-use &>/dev/null && ok "browser-use available" || warn "browser-use not found"
  [ -f "$CLAUDE_DIR/scripts/statusline.py" ] && ok "statusline script" || warn "statusline not found"
  python3 -c "import json; d=json.load(open('$HOME/.claude.json')); assert 'mind' in d.get('mcpServers',{})" 2>/dev/null && ok "mind MCP" || warn "mind MCP not registered"
  python3 -c "import json; d=json.load(open('$HOME/.claude.json')); assert 'codedb' in d.get('mcpServers',{})" 2>/dev/null && ok "codedb MCP" || warn "codedb MCP not registered"
  [ -f "$CLAUDE_DIR/scripts/show.py" ] && ok "dashboard (show.py)" || warn "dashboard not found"
  command -v codex &>/dev/null && ok "codex CLI" || warn "codex CLI not found"
  [ -f "$HOME/.codex/config.toml" ] && ok "codex config.toml" || warn "codex config.toml not found"
  [ -f "$HOME/.codex/AGENTS.md" ] && ok "codex AGENTS.md" || warn "codex AGENTS.md not found"
  [ -f "$HOME/.codex/hooks.json" ] && ok "codex hooks.json" || warn "codex hooks.json not found"
  command -v opencode &>/dev/null && ok "opencode CLI" || warn "opencode CLI not found"
  [ -f "$HOME/.config/opencode/opencode.json" ] && ok "opencode config" || warn "opencode config not found"

  echo ""
  info "Deployed configuration:"
  for f in CLAUDE.md NTO.md rules/*.md skills/*/SKILL.md hooks/*.sh; do
    [ -f "$CLAUDE_DIR/$f" ] && echo "  ✓ $f"
  done
fi

# ── Bootstrap environment snapshot ──
bash "$CLAUDE_DIR/hooks/env-bootstrap.sh" 2>/dev/null || true
ok "Environment snapshot"

# ── Adapter auto-detection ──
phase "Phase 5: Adapter Auto-Detection"
# Ensure opencode binary is findable (installs to ~/.opencode/bin)
export PATH="$HOME/.opencode/bin:$PATH"
if [ -d "$ADAPTERS_DIR" ]; then
  MIND_SERVER="$HOME/.mind/mem/server.py"
  MEM_PYTHON="$HOME/.mind/venv/bin/python3"
  [ ! -x "$MEM_PYTHON" ] && MEM_PYTHON="python3"
  for adapter_file in "$ADAPTERS_DIR"/*.json; do
    [ -f "$adapter_file" ] || continue
    adapter_name="$(basename "$adapter_file" .json)"
    [ "$adapter_name" = "claude-code" ] && continue  # Already configured
    if [ "$adapter_name" = "codex" ]; then
      # Codex needs full harness, not just MCP config
      if command -v codex &>/dev/null || [ -d "$HOME/.codex" ]; then
        info "Detected: codex — deploying full harness..."
        deploy_codex_harness && ok "codex adapter" || warn "codex adapter failed"
      fi
      continue
    fi
    if [ "$adapter_name" = "opencode" ]; then
      # OpenCode needs full harness, not just MCP config
      if command -v opencode &>/dev/null; then
        info "Detected: opencode — deploying harness..."
        deploy_opencode_harness && ok "opencode adapter" || warn "opencode adapter failed"
      fi
      continue
    fi
    detect_cmd=$(python3 -c "import json; print(json.load(open('$adapter_file')).get('detect','false'))" 2>/dev/null || echo "false")
    if eval "$detect_cmd" &>/dev/null; then
      info "Detected: $adapter_name — configuring..."
      "$0" --adapter "$adapter_name" && ok "$adapter_name adapter" || warn "$adapter_name adapter failed"
    fi
  done
fi

# ── First-run hint ──
if [ ! -f "$HOME/.mind/onboarded" ]; then
  echo ""
  info "First time? Run /onboard to set up personal preferences."
fi

# ── Done ──
echo ""
printf "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}\n"
printf "${GREEN}║              keep — Ready!                          ║${NC}\n"
printf "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}\n"
printf "${GREEN}║${NC}                                                          ${GREEN}║${NC}\n"
printf "${GREEN}║${NC}  ${CYAN}claude${NC}             Main orchestrator                 ${GREEN}║${NC}\n"
printf "${GREEN}║${NC}  ${CYAN}mx${NC}                 Model switcher (mx set)           ${GREEN}║${NC}\n"
printf "${GREEN}║${NC}  ${CYAN}codex${NC}              Codex CLI (OpenAI)                ${GREEN}║${NC}\n"
printf "${GREEN}║${NC}  ${CYAN}opencode${NC}           OpenCode CLI                      ${GREEN}║${NC}\n"
printf "${GREEN}║${NC}  ${CYAN}codedb${NC}             Code intelligence (MCP)           ${GREEN}║${NC}\n"
printf "${GREEN}║${NC}  ${CYAN}browser-use${NC}        Headless browser automation       ${GREEN}║${NC}\n"
printf "${GREEN}║${NC}  ${CYAN}nto${NC}                Native token optimizer             ${GREEN}║${NC}\n"
printf "${GREEN}║${NC}  ${CYAN}statusline${NC}         Token/cost/context status bar     ${GREEN}║${NC}\n"
printf "${GREEN}║${NC}                                                          ${GREEN}║${NC}\n"
printf "${GREEN}║${NC}  ${YELLOW}Skills:${NC}                                                ${GREEN}║${NC}\n"
printf "${GREEN}║${NC}    /sprint       Think→Plan→Build→Review→Test→Ship       ${GREEN}║${NC}\n"
printf "${GREEN}║${NC}    /review       Cross-validated code review             ${GREEN}║${NC}\n"
printf "${GREEN}║${NC}    /statusline   Token/cost/context status bar           ${GREEN}║${NC}\n"
printf "${GREEN}║${NC}    /browser-use  Headless browser automation             ${GREEN}║${NC}\n"
printf "${GREEN}║${NC}                                                          ${GREEN}║${NC}\n"
printf "${GREEN}║${NC}  ${YELLOW}Safety:${NC}                                                ${GREEN}║${NC}\n"
printf "${GREEN}║${NC}    safety-guard.sh  Blocks destructive commands           ${GREEN}║${NC}\n"
printf "${GREEN}║${NC}    nto-rewrite.sh   Token-optimized command rewriter      ${GREEN}║${NC}\n"
printf "${GREEN}║${NC}                                                          ${GREEN}║${NC}\n"
printf "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}\n"
echo ""
info "Run 'source ~/.bashrc' or open a new terminal."
info "Configure API provider before first use:"
info "  mx set <model> <api-key>    # e.g. mx set glm-5 xxx"
info "  Anthropic:  export ANTHROPIC_API_KEY=xxx && claude"
