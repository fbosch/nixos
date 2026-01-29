#!/usr/bin/env bash
# Chromium Apps Maintenance Script

set -e

echo "🔧 Chromium Apps Maintenance"
echo "============================"

# Check for available chromium apps
echo "📦 Available Chromium Apps:"
APPS=$(cd ~/nixos && nix flake show 2>/dev/null | grep "chromium-" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/.*chromium-/chromium-/' | sed 's/[[:space:]].*//' | sed 's/:$//' | sort -u)
echo "$APPS"

echo ""
echo "🔍 Checking for updates..."
cd ~/nixos
if git status --porcelain | grep -q .; then
    echo "⚠️  Working directory has uncommitted changes"
    echo "   Run 'git status' to see changes"
else
    echo "✅ Working directory is clean"
fi

echo ""
echo "🧪 Testing builds..."
for app in $APPS; do
    echo "   Testing $app..."
    if nix build ".#$app" 2>/dev/null; then
        echo "   ✅ $app builds successfully"
    else
        echo "   ❌ $app failed to build"
    fi
done

echo ""
echo "💡 Tips:"
echo "   - Run 'nix run .#fmt' to format code"
echo "   - Run 'nix flake update' to update dependencies"
echo "   - Check logs with 'journalctl -f' during testing"
