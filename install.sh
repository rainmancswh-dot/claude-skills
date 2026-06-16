#!/usr/bin/env bash
set -euo pipefail

# Claude Code Skills Installer (with dependency resolution)
# Usage:
#   Local:  ./install.sh [--all] [skill-name...]
#   Remote: bash <(curl -fsSL .../install.sh) [--all] [skill-name...]
#   No args → install core skills + check deps

REPO="rainmancswh-dot/claude-skills"
BRANCH="main"
SKILLS_DIR="$HOME/.claude/skills"
DEFAULT_SKILLS=(api-design flow-extract frontend-test spec-dev spec-verify design-prototype)
AVAILABLE_SKILLS=(api-design flow-extract frontend-test spec-dev spec-verify design-prototype)

# ── External dependencies ──────────────────────────────────
# Format: "name|check_path|install_cmd|auto"
# auto=true means we can install it silently; auto=false means user interaction needed

declare -a DEPS
DEPS+=("gstack|$HOME/.claude/skills/gstack/SKILL.md|setup-gstack|false")
DEPS+=("superpowers|$HOME/.claude/plugins/cache/superpowers-marketplace|setup-superpowers|false")
DEPS+=("grill-with-docs|$HOME/.claude/skills/grill-with-docs/SKILL.md|setup-grill|true")

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }
step()  { echo -e "${BLUE}→${NC} $1"; }

# ── Dependency helpers ─────────────────────────────────────

setup-grill() {
  step "Installing grill-with-docs from mattpocock/skills..."
  local dir="$HOME/.claude/skills/grill-with-docs"
  mkdir -p "$dir"

  local files=(
    "SKILL.md"
    "CONTEXT-FORMAT.md"
    "ADR-FORMAT.md"
  )
  local base="https://raw.githubusercontent.com/mattpocock/skills/main/skills/engineering/grill-with-docs"

  for f in "${files[@]}"; do
    if curl -fsSL --retry 2 "$base/$f" -o "$dir/$f" 2>/dev/null; then
      info "grill-with-docs: downloaded $f"
    else
      error "grill-with-docs: failed to download $f"
      return 1
    fi
  done
  info "grill-with-docs: installed"
}

setup-gstack() {
  warn "gstack not found."
  echo ""
  echo "  gstack is a separate skill suite. To install:"
  echo "    1. git clone <gstack-repo> ~/.claude/skills/gstack"
  echo "    2. cd ~/.claude/skills/gstack && ./setup"
  echo ""
  echo "  Or check: https://github.com/garrytan/gstack"
}

setup-superpowers() {
  warn "superpowers plugin not found."
  echo ""
  echo "  superpowers is a Claude Code plugin. To install:"
  echo "    Run in Claude Code: /plugin install superpowers@superpowers-marketplace"
  echo ""
}

check_deps() {
  echo ""
  echo "── Checking Dependencies ─────────"
  echo ""

  local missing=()
  local auto_fixed=()

  for dep in "${DEPS[@]}"; do
    IFS='|' read -r name check_path setup_fn auto <<< "$dep"

    if [ -f "$check_path" ] || [ -d "$check_path" ]; then
      info "$name: found"
    else
      warn "$name: missing"
      if [ "$auto" = "true" ]; then
        if "$setup_fn"; then
          auto_fixed+=("$name")
        else
          missing+=("$name")
        fi
      else
        "$setup_fn"
        missing+=("$name")
      fi
    fi
  done

  echo ""

  if [ ${#auto_fixed[@]} -gt 0 ]; then
    info "Auto-installed: ${auto_fixed[*]}"
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    warn "Manual install needed: ${missing[*]}"
    echo "  (see instructions above)"
  fi
}

# ── Detect install mode ────────────────────────────────────

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

# ── Parse args ─────────────────────────────────────────────

INSTALL_ALL=false
INSTALL_SKILLS=()
for arg in "$@"; do
  case "$arg" in
    --all) INSTALL_ALL=true ;;
    --check-deps) check_deps; exit 0 ;;
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

# ── Main ───────────────────────────────────────────────────

echo ""
echo "🛠  Claude Code Skills Installer"
echo "   Skills dir: $SKILLS_DIR"
echo "   Installing: ${INSTALL_SKILLS[*]}"
echo ""

# Check dependencies first
check_deps

# Create skills directory
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
echo "  Restart Claude Code and run:"
echo "    /office-hours     — 需求讨论"
echo "    /grill-with-docs  — 建立领域语言"
echo "    /plan-ceo-review  — 需求评审"
echo "    /plan-eng-review  — 技术评审"
echo "    /api-design       — API 契约"
echo "    /flow-extract     — 交互流程"
echo "    /design-prototype — 原型设计"
echo "    /spec-dev         — 规格驱动开发"
echo "    /spec-verify      — 一致性验证"
echo "    /frontend-test    — 前端组件测试"
echo ""
