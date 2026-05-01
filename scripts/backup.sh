#!/bin/bash
# ============================================================
# backup.sh — keep Backup
# Backs up keep modules independently or all at once.
#
# Usage:
#   ./scripts/backup.sh               # Full backup (all modules)
#   ./scripts/backup.sh mind          # Mind data only (~/.mind)
#   ./scripts/backup.sh claude        # Claude config only (~/.claude)
#   ./scripts/backup.sh codedb        # codedb data only (~/.codedb)
# ============================================================

set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-$HOME/.claude/backups}"
mkdir -p "$BACKUP_DIR"

# ── Module definitions ──
# Each module: name | home_dir | tar_excludes
declare -A MOD_DIR
MOD_DIR[mind]="$HOME/.mind"
MOD_DIR[claude]="$HOME/.claude"
MOD_DIR[codedb]="$HOME/.codedb"

declare -A MOD_EXCLUDES
MOD_EXCLUDES[mind]="--exclude=.git --exclude=venv --exclude=__pycache__ --exclude=*.db-shm --exclude=*.db-wal --exclude=backups"
MOD_EXCLUDES[claude]="--exclude=.git --exclude=worktrees --exclude=__pycache__ --exclude=logs --exclude=backups"
MOD_EXCLUDES[codedb]="--exclude=.git --exclude=__pycache__"

# ── Parse args ──
MODULE="${1:-all}"

backup_module() {
  local name="$1"
  local dir="${MOD_DIR[$name]}"
  local excludes="${MOD_EXCLUDES[$name]}"

  if [ ! -d "$dir" ]; then
    echo "Skip: $name ($dir not found)"
    return
  fi

  local outfile="$BACKUP_DIR/${name}.tar.gz"
  local basepath=$(basename "$dir")
  local parent=$(dirname "$dir")

  local tar_err=$(mktemp)
  if tar -czf "$outfile" $excludes -C "$parent" "$basepath" 2>"$tar_err"; then
    local size=$(du -h "$outfile" | cut -f1)
    echo "  $name: $outfile ($size)"
  elif [ -f "$outfile" ] && [ -s "$outfile" ]; then
    # Partial backup (e.g. file changed during read) — still usable
    local size=$(du -h "$outfile" | cut -f1)
    echo "  $name: $outfile ($size, warnings)"
  else
    echo "  $name: backup failed" >&2
    cat "$tar_err" >&2
    rm -f "$outfile" 2>/dev/null || true
  fi
  rm -f "$tar_err"
}

# ── Run ──
echo "keep Backup"

if [ "$MODULE" = "all" ]; then
  echo "  Modules: mind claude codedb"
  backup_module "mind"
  backup_module "claude"
  backup_module "codedb"
elif [ -n "${MOD_DIR[$MODULE]:-}" ]; then
  echo "  Module: $MODULE"
  backup_module "$MODULE"
else
  echo "Unknown module: $MODULE" >&2
  echo "Available: mind, claude, codedb, all" >&2
  exit 1
fi

echo "  Done"
