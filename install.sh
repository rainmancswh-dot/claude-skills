#!/usr/bin/env bash
set -euo pipefail

# Claude Code Skills Installer
# Usage:
#   Local:  ./install.sh [--all] [skill-name...]
#   Remote: bash <(curl -fsSL .../install.sh) [--all] [skill-name...]
#   No args → install 3 core skills; --all → install all 5

REPO="rainmancswh-dot/claude-skills"
BRANCH="main"
SKILLS_DIR="$HOME/.claude/skills"
DEFAULT_SKILLS=(api-design flow-extract frontend-test)
AVAILABLE_SKILLS=(api-design flow-extract frontend-test spec-dev spec-verify)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }

# Detect if running remotely (curl | bash) — no local skill files
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
REMOTE_MODE=false

if [ ! -d "$SCRIPT_DIR/api-design" ]; then
  REMOTE_MODE=true
  CLONE_DIR=$(mktemp -d)
  cleanup() { rm -rf "$CLONE_DIR"; }
  trap cleanup EXIT

  echo ""
  echo "📦 Remote install detected, cloning $REPO..."
  if ! git clone --depth 1 -b "$BRANCH" "https://github.com/$REPO.git" "$CLONE_DIR" 2>/dev/null; then
    error "Failed to clone https://github.com/$REPO"
    exit 1
  fi
  SCRIPT_DIR="$CLONE_DIR"
  info "Cloned successfully"
fi

# Determine which skills to install
INSTALL_ALL=false
INSTALL_SKILLS=()
for arg in "$@"; do
  case "$arg" in
    --all) INSTALL_ALL=true ;;
    *)
      if [[ " ${AVAILABLE_SKILLS[*]} " == *" $arg "* ]]; then
        INSTALL_SKILLS+=("$arg")
      else
        error "Unknown skill: $arg (available: ${AVAILABLE_SKILLS[*]})"
        exit 1
      fi
      ;;
  esac
done

if [ ${#INSTALL_SKILLS[@]} -eq 0 ]; then
  if [ "$INSTALL_ALL" = true ]; then
    INSTALL_SKILLS=("${AVAILABLE_SKILLS[@]}")
  else
    INSTALL_SKILLS=("${DEFAULT_SKILLS[@]}")
  fi
fi

echo ""
echo "🛠  Claude Code Skills Installer"
echo "   Skills dir: $SKILLS_DIR"
echo "   Installing: ${INSTALL_SKILLS[*]}"
echo ""

# Create skills directory if needed
mkdir -p "$SKILLS_DIR"

INSTALLED=()
FAILED=()

for skill in "${INSTALL_SKILLS[@]}"; do
  TARGET="$SKILLS_DIR/$skill"
  SOURCE="$SCRIPT_DIR/$skill"

  if [ ! -d "$SOURCE" ]; then
    error "$skill: source directory not found"
    FAILED+=("$skill")
    continue
  fi

  # Backup existing skill
  if [ -d "$TARGET" ]; then
    BACKUP="$TARGET.bak.$(date +%Y%m%d%H%M%S)"
    mv "$TARGET" "$BACKUP"
    warn "$skill: backed up existing to $BACKUP"
  fi

  # Copy skill
  if cp -r "$SOURCE" "$TARGET"; then
    info "$skill: installed"
    INSTALLED+=("$skill")
  else
    error "$skill: copy failed"
    FAILED+=("$skill")
  fi
done

echo ""
echo "── Results ──────────────────────"
if [ ${#INSTALLED[@]} -gt 0 ]; then
  info "Installed: ${INSTALLED[*]}"
fi
if [ ${#FAILED[@]} -gt 0 ]; then
  error "Failed: ${FAILED[*]}"
fi

echo ""
echo "Usage: restart Claude Code, then run:"
for skill in "${INSTALLED[@]}"; do
  echo "  /$skill"
done
echo ""
