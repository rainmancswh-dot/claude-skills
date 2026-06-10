#!/usr/bin/env bash
set -euo pipefail

# Claude Code Skills Uninstaller
# Usage: ./uninstall.sh [skill-name...]
#   No args  → uninstall all 3 skills
#   With args → uninstall only named skills

SKILLS_DIR="$HOME/.claude/skills"
AVAILABLE_SKILLS=(api-design flow-extract frontend-test)

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }

if [ $# -eq 0 ]; then
  UNINSTALL_SKILLS=("${AVAILABLE_SKILLS[@]}")
else
  UNINSTALL_SKILLS=()
  for name in "$@"; do
    if [[ " ${AVAILABLE_SKILLS[*]} " == *" $name "* ]]; then
      UNINSTALL_SKILLS+=("$name")
    else
      error "Unknown skill: $name"
      exit 1
    fi
  done
fi

echo ""
echo "🗑  Claude Code Skills Uninstaller"
echo ""

for skill in "${UNINSTALL_SKILLS[@]}"; do
  TARGET="$SKILLS_DIR/$skill"
  if [ -d "$TARGET" ]; then
    rm -rf "$TARGET"
    info "$skill: removed"
  else
    warn "$skill: not installed, skipping"
  fi
done

echo ""
info "Done. Restart Claude Code to take effect."
echo ""
