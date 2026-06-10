#!/usr/bin/env bash
set -euo pipefail

# Remote installer — curl | bash entry point
# Clones the repo to a temp dir and runs the local install.sh

REPO="rainmancswh-dot/claude-skills"
BRANCH="main"
TMPDIR=$(mktemp -d)

cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

echo "📦 Cloning $REPO..."
if ! git clone --depth 1 -b "$BRANCH" "https://github.com/$REPO.git" "$TMPDIR/repo" 2>/dev/null; then
  echo "✗ Failed to clone. Check the repo URL: https://github.com/$REPO"
  exit 1
fi

echo ""
bash "$TMPDIR/repo/install.sh" "$@"
