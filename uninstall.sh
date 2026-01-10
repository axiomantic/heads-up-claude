#!/bin/bash
set -e

echo "Heads Up Claude - Uninstaller"
echo "=============================="
echo

# Files to remove
BINARY="$HOME/.local/bin/heads-up-claude"
EXPECT_SCRIPT="$HOME/.local/bin/get_usage.exp"
CONFIG_FILE="$HOME/.claude/heads_up_config.json"
CACHE_DIR="${TMPDIR:-/tmp}/heads-up-claude"

# Check what exists
echo "Checking installed components..."
echo

found_something=false

if [ -f "$BINARY" ]; then
    echo "  [x] Binary: $BINARY"
    found_something=true
else
    echo "  [ ] Binary: $BINARY (not found)"
fi

if [ -f "$EXPECT_SCRIPT" ]; then
    echo "  [x] Expect script: $EXPECT_SCRIPT"
    found_something=true
else
    echo "  [ ] Expect script: $EXPECT_SCRIPT (not found)"
fi

if [ -f "$CONFIG_FILE" ]; then
    echo "  [x] Config: $CONFIG_FILE"
    found_something=true
else
    echo "  [ ] Config: $CONFIG_FILE (not found)"
fi

if [ -d "$CACHE_DIR" ]; then
    echo "  [x] Cache: $CACHE_DIR"
    found_something=true
else
    echo "  [ ] Cache: $CACHE_DIR (not found)"
fi

echo

if [ "$found_something" = false ]; then
    echo "Nothing to uninstall."
    exit 0
fi

# Confirm
read -p "Remove these files? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo
echo "Removing files..."

# Remove files
[ -f "$BINARY" ] && rm -f "$BINARY" && echo "  Removed $BINARY"
[ -f "$EXPECT_SCRIPT" ] && rm -f "$EXPECT_SCRIPT" && echo "  Removed $EXPECT_SCRIPT"
[ -f "$CONFIG_FILE" ] && rm -f "$CONFIG_FILE" && echo "  Removed $CONFIG_FILE"
[ -d "$CACHE_DIR" ] && rm -rf "$CACHE_DIR" && echo "  Removed $CACHE_DIR"

# Kill any running background processes
pkill -f "heads-up-claude/refresh.sh" 2>/dev/null && echo "  Killed background refresh processes" || true

echo

# Remove statusLine from settings.json
SETTINGS_FILE="$HOME/.claude/settings.json"
if [ -f "$SETTINGS_FILE" ]; then
    if grep -q "statusLine" "$SETTINGS_FILE"; then
        echo "Removing statusLine config from $SETTINGS_FILE..."
        if command -v jq &> /dev/null; then
            # Use jq if available (clean JSON handling)
            tmp_settings=$(mktemp)
            jq 'del(.statusLine)' "$SETTINGS_FILE" > "$tmp_settings" && mv "$tmp_settings" "$SETTINGS_FILE"
            echo "  Removed statusLine entry"
        else
            # Fallback: warn user to do it manually
            echo "  Warning: jq not found. Please manually remove 'statusLine' from $SETTINGS_FILE"
        fi
    fi
fi

echo
echo "Uninstall complete."
