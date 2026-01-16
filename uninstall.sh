#!/bin/bash
set -e

echo "Heads Up Claude - Uninstaller"
echo "=============================="
echo

# ─────────────────────────────────────────────────────────────────
# Detect Claude config directories (same logic as install.sh)
# ─────────────────────────────────────────────────────────────────
detect_claude_dirs() {
    local found_dirs=()

    # Check CLAUDE_CONFIG_DIR environment variable first
    if [ -n "$CLAUDE_CONFIG_DIR" ] && [ -d "$CLAUDE_CONFIG_DIR" ]; then
        found_dirs+=("$CLAUDE_CONFIG_DIR")
    fi

    # Common locations
    for dir in "$HOME/.claude" "$HOME/.claude-work" "$HOME/.config/claude"; do
        if [ -d "$dir" ] && [[ ! " ${found_dirs[*]} " =~ " ${dir} " ]]; then
            found_dirs+=("$dir")
        fi
    done

    # Search for directories containing Claude markers
    while IFS= read -r -d '' dir; do
        local parent_dir=$(dirname "$dir")
        if [[ ! " ${found_dirs[*]} " =~ " ${parent_dir} " ]]; then
            found_dirs+=("$parent_dir")
        fi
    done < <(find "$HOME" -maxdepth 3 -name "CLAUDE.md" -print0 2>/dev/null || true)

    while IFS= read -r -d '' dir; do
        local parent_dir=$(dirname "$dir")
        if [[ ! " ${found_dirs[*]} " =~ " ${parent_dir} " ]]; then
            found_dirs+=("$parent_dir")
        fi
    done < <(find "$HOME" -maxdepth 3 -name "settings.json" -print0 2>/dev/null | xargs -0 grep -l "statusLine" 2>/dev/null || true)

    echo "${found_dirs[@]}"
}

# ─────────────────────────────────────────────────────────────────
# Binary and service files (same for all config dirs)
# ─────────────────────────────────────────────────────────────────
HUC_BINARY="$HOME/.local/bin/huc"
HUCD_BINARY="$HOME/.local/bin/hucd"
SYMLINK_BINARY="$HOME/.local/bin/heads-up-claude"
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/com.headsup.claude.plist"
SYSTEMD_SERVICE="$HOME/.config/systemd/user/hucd.service"
DAEMON_LOG_DIR="$HOME/.local/share/hucd"

# Legacy files
LEGACY_BINARY="$HOME/.local/bin/heads-up-claude"
LEGACY_EXPECT="$HOME/.local/bin/get_usage.exp"
LEGACY_CACHE="${TMPDIR:-/tmp}/heads-up-claude"

# ─────────────────────────────────────────────────────────────────
# Detect all Claude config directories
# ─────────────────────────────────────────────────────────────────
echo "Detecting Claude config directories..."
CLAUDE_DIRS=($(detect_claude_dirs))

if [ ${#CLAUDE_DIRS[@]} -eq 0 ]; then
    # Fallback to default
    CLAUDE_DIRS=("$HOME/.claude")
fi

echo "  Found: ${CLAUDE_DIRS[*]}"
echo

# ─────────────────────────────────────────────────────────────────
# Check what exists
# ─────────────────────────────────────────────────────────────────
echo "Checking installed components..."
echo

found_something=false

echo "Binaries and services:"
if [ -f "$HUC_BINARY" ]; then
    echo "  [x] huc binary: $HUC_BINARY"
    found_something=true
else
    echo "  [ ] huc binary: (not found)"
fi

if [ -f "$HUCD_BINARY" ]; then
    echo "  [x] hucd binary: $HUCD_BINARY"
    found_something=true
else
    echo "  [ ] hucd binary: (not found)"
fi

if [ -L "$SYMLINK_BINARY" ]; then
    echo "  [x] Symlink: $SYMLINK_BINARY -> $(readlink "$SYMLINK_BINARY")"
    found_something=true
fi

if [ -f "$LAUNCHD_PLIST" ]; then
    echo "  [x] launchd plist: $LAUNCHD_PLIST"
    found_something=true
    # Check if daemon is currently loaded
    if launchctl list 2>/dev/null | grep -q "com.headsup.claude"; then
        echo "      (daemon is running)"
    fi
else
    echo "  [ ] launchd plist: (not found)"
fi

if [ -f "$SYSTEMD_SERVICE" ]; then
    echo "  [x] systemd service: $SYSTEMD_SERVICE"
    found_something=true
    # Check if daemon is currently active
    if systemctl --user is-active hucd >/dev/null 2>&1; then
        echo "      (daemon is running)"
    fi
else
    echo "  [ ] systemd service: (not found)"
fi

if [ -d "$DAEMON_LOG_DIR" ]; then
    echo "  [x] Daemon logs: $DAEMON_LOG_DIR"
    found_something=true
else
    echo "  [ ] Daemon logs: (not found)"
fi

echo
echo "Config directories:"
for config_dir in "${CLAUDE_DIRS[@]}"; do
    display_dir="${config_dir/#$HOME/\~}"

    # Check for heads-up-cache
    if [ -d "$config_dir/heads-up-cache" ]; then
        echo "  [x] $display_dir/heads-up-cache/"
        found_something=true
    fi

    # Check for legacy config
    if [ -f "$config_dir/heads_up_config.json" ]; then
        echo "  [x] $display_dir/heads_up_config.json"
        found_something=true
    fi

    # Check for statusLine in settings.json
    if [ -f "$config_dir/settings.json" ] && grep -q "statusLine" "$config_dir/settings.json" 2>/dev/null; then
        echo "  [x] $display_dir/settings.json (contains statusLine)"
        found_something=true
    fi
done

echo
echo "Legacy files:"
if [ -f "$LEGACY_BINARY" ] && [ ! -L "$LEGACY_BINARY" ]; then
    echo "  [x] Legacy binary: $LEGACY_BINARY"
    found_something=true
else
    echo "  [ ] Legacy binary: (not found)"
fi

if [ -f "$LEGACY_EXPECT" ]; then
    echo "  [x] Expect script: $LEGACY_EXPECT"
    found_something=true
else
    echo "  [ ] Expect script: (not found)"
fi

if [ -d "$LEGACY_CACHE" ]; then
    echo "  [x] Legacy cache: $LEGACY_CACHE"
    found_something=true
else
    echo "  [ ] Legacy cache: (not found)"
fi

echo

if [ "$found_something" = false ]; then
    echo "Nothing to uninstall."
    exit 0
fi

# ─────────────────────────────────────────────────────────────────
# Confirm
# ─────────────────────────────────────────────────────────────────
read -p "Remove these files? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo
echo "Removing files..."

# ─────────────────────────────────────────────────────────────────
# Stop daemon services first
# ─────────────────────────────────────────────────────────────────
echo "Stopping daemon services..."

if [ "$(uname)" = "Darwin" ]; then
    if [ -f "$LAUNCHD_PLIST" ]; then
        launchctl unload "$LAUNCHD_PLIST" 2>/dev/null && echo "  Stopped launchd service" || true
    fi
else
    systemctl --user stop hucd 2>/dev/null && echo "  Stopped systemd service" || true
    systemctl --user disable hucd 2>/dev/null || true
fi

# Kill any orphaned daemon processes
pkill -f "hucd" 2>/dev/null && echo "  Killed orphaned hucd processes" || true

echo

# ─────────────────────────────────────────────────────────────────
# Remove binaries and services
# ─────────────────────────────────────────────────────────────────
[ -L "$SYMLINK_BINARY" ] && rm -f "$SYMLINK_BINARY" && echo "  Removed symlink $SYMLINK_BINARY"
[ -f "$HUC_BINARY" ] && rm -f "$HUC_BINARY" && echo "  Removed $HUC_BINARY"
[ -f "$HUCD_BINARY" ] && rm -f "$HUCD_BINARY" && echo "  Removed $HUCD_BINARY"
[ -f "$LAUNCHD_PLIST" ] && rm -f "$LAUNCHD_PLIST" && echo "  Removed $LAUNCHD_PLIST"
[ -f "$SYSTEMD_SERVICE" ] && rm -f "$SYSTEMD_SERVICE" && echo "  Removed $SYSTEMD_SERVICE"
[ -d "$DAEMON_LOG_DIR" ] && rm -rf "$DAEMON_LOG_DIR" && echo "  Removed $DAEMON_LOG_DIR"

# Reload systemd if service was removed
if [ "$(uname)" != "Darwin" ] && [ -d "$HOME/.config/systemd/user" ]; then
    systemctl --user daemon-reload 2>/dev/null || true
fi

# ─────────────────────────────────────────────────────────────────
# Remove config from all detected Claude directories
# ─────────────────────────────────────────────────────────────────
for config_dir in "${CLAUDE_DIRS[@]}"; do
    display_dir="${config_dir/#$HOME/\~}"

    # Remove cache directory
    if [ -d "$config_dir/heads-up-cache" ]; then
        rm -rf "$config_dir/heads-up-cache"
        echo "  Removed $display_dir/heads-up-cache/"
    fi

    # Remove legacy config
    if [ -f "$config_dir/heads_up_config.json" ]; then
        rm -f "$config_dir/heads_up_config.json"
        echo "  Removed $display_dir/heads_up_config.json"
    fi

    # Remove statusLine from settings.json
    if [ -f "$config_dir/settings.json" ] && grep -q "statusLine" "$config_dir/settings.json" 2>/dev/null; then
        if command -v jq &> /dev/null; then
            tmp_settings=$(mktemp)
            jq 'del(.statusLine)' "$config_dir/settings.json" > "$tmp_settings" && mv "$tmp_settings" "$config_dir/settings.json"
            echo "  Removed statusLine from $display_dir/settings.json"
        else
            echo "  Warning: jq not found. Please manually remove 'statusLine' from $display_dir/settings.json"
        fi
    fi
done

# ─────────────────────────────────────────────────────────────────
# Remove legacy files
# ─────────────────────────────────────────────────────────────────
[ -f "$LEGACY_BINARY" ] && [ ! -L "$LEGACY_BINARY" ] && rm -f "$LEGACY_BINARY" && echo "  Removed legacy $LEGACY_BINARY"
[ -f "$LEGACY_EXPECT" ] && rm -f "$LEGACY_EXPECT" && echo "  Removed $LEGACY_EXPECT"
[ -d "$LEGACY_CACHE" ] && rm -rf "$LEGACY_CACHE" && echo "  Removed $LEGACY_CACHE"

# Remove nimble shims if present
NIMBLE_BIN="$HOME/.nimble/bin"
if [ -d "$NIMBLE_BIN" ]; then
    for shim in "huc" "hucd" "heads-up-claude"; do
        if [ -f "$NIMBLE_BIN/$shim" ]; then
            rm -f "$NIMBLE_BIN/$shim"
            echo "  Removed nimble shim: $NIMBLE_BIN/$shim"
        fi
    done
fi

echo
echo "Uninstall complete."
