#!/usr/bin/env bash
set -euo pipefail

# Claude Code Skills Installer
# Usage: ./install.sh [skill-name...]
#   No args  → install all 3 skills
#   With args → install only named skills (api-design, flow-extract, frontend-test)

SKILLS_DIR="$HOME/.claude/skills"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AVAILABLE_SKILLS=(api-design flow-extract frontend-test)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }

# Determine which skills to install
if [ $# -eq 0 ]; then
  INSTALL_SKILLS=("${AVAILABLE_SKILLS[@]}")
else
  INSTALL_SKILLS=()
  for name in "$@"; do
    if [[ " ${AVAILABLE_SKILLS[*]} " == *" $name "* ]]; then
      INSTALL_SKILLS+=("$name")
    else
      error "Unknown skill: $name (available: ${AVAILABLE_SKILLS[*]})"
      exit 1
    fi
  done
fi

echo ""
echo "🛠  Claude Code Skills Installer"
echo "   Skills dir: $SKILLS_DIR"
echo "   Installing: ${INSTALL_SKILLS[*]}"
echo ""

# Create skills directory if needed
mkdir -p "$SKILLS_DIR"

INSTALLED=()
SKIPPED=()
FAILED=()

for skill in "${INSTALL_SKILLS[@]}"; do
  TARGET="$SKILLS_DIR/$skill"
  SOURCE="$SCRIPT_DIR/$skill"

  if [ ! -d "$SOURCE" ]; then
    error "$skill: source directory not found (are you running from the repo root?)"
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
if [ ${#SKIPPED[@]} -gt 0 ]; then
  warn "Skipped: ${SKIPPED[*]}"
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
