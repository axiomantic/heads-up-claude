#!/usr/bin/env bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Unicode symbols
CHECK="${GREEN}✓${NC}"
CROSS="${RED}✗${NC}"
ARROW="${BLUE}→${NC}"
INFO="${CYAN}ℹ${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Default config directory
CLAUDE_CONFIG_DIR="$HOME/.claude"

print_help() {
    echo "Heads Up Claude - Installation Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --clear                     Clear ALL settings and config before installing"
    echo "                              (removes statusLine config and plan config)"
    echo "  --claude-config-dir=PATH    Claude config directory"
    echo "                              If not specified, installer will auto-detect"
    echo "                              existing Claude directories and prompt for selection"
    echo "  --help, -h                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Auto-detect and prompt for selection"
    echo "  $0 --clear                            # Fresh install, clear all previous config"
    echo "  $0 --claude-config-dir=~/.claude-work # Install with specific config directory"
    echo ""
    echo "Auto-detection:"
    echo "  The installer searches for directories containing Claude markers"
    echo "  in your home directory and prompts you to select which one to use."
    echo ""
    exit 0
}

print_header() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  Heads Up Claude - Installation Script                   ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo -e "${ARROW} $1"
}

print_success() {
    echo -e "${CHECK} $1"
}

print_error() {
    echo -e "${CROSS} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}⚠${NC}  $1"
}

print_info() {
    echo -e "${INFO} $1"
}

cleanup_all() {
    echo ""
    print_step "Cleaning up existing installation..."

    # Kill orphaned processes
    print_step "Stopping any running processes..."
    pkill -9 -f "heads-up-claude" 2>/dev/null || true
    sleep 1

    # Remove legacy binaries
    local legacy_files=(
        "$HOME/.local/bin/heads-up-claude"
        "$HOME/.local/bin/get_usage.exp"
    )
    for f in "${legacy_files[@]}"; do
        if [ -f "$f" ] && [ ! -L "$f" ]; then
            rm -f "$f"
            print_success "Removed legacy file: $f"
        fi
    done

    # Remove symlink
    if [ -L "$HOME/.local/bin/heads-up-claude" ]; then
        rm -f "$HOME/.local/bin/heads-up-claude"
        print_success "Removed symlink: ~/.local/bin/heads-up-claude"
    fi

    # Remove huc binary
    if [ -f "$HOME/.local/bin/huc" ]; then
        rm -f "$HOME/.local/bin/huc"
        print_success "Removed: $HOME/.local/bin/huc"
    fi

    # Remove legacy daemon binaries and services
    if [ -f "$HOME/.local/bin/hucd" ]; then
        rm -f "$HOME/.local/bin/hucd"
        print_success "Removed legacy daemon: $HOME/.local/bin/hucd"
    fi

    # Stop and remove legacy daemon services
    if [[ "$OSTYPE" == "darwin"* ]]; then
        local plist_path="$HOME/Library/LaunchAgents/com.headsup.claude.plist"
        if [ -f "$plist_path" ]; then
            launchctl unload "$plist_path" 2>/dev/null || true
            rm -f "$plist_path"
            print_success "Removed legacy launchd plist"
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        local service_path="$HOME/.config/systemd/user/hucd.service"
        if [ -f "$service_path" ]; then
            systemctl --user stop hucd.service 2>/dev/null || true
            systemctl --user disable hucd.service 2>/dev/null || true
            rm -f "$service_path"
            systemctl --user daemon-reload 2>/dev/null || true
            print_success "Removed legacy systemd service"
        fi
    fi
    pkill -9 -f "hucd" 2>/dev/null || true

    # Remove legacy daemon config and logs
    if [ -d "$HOME/.config/hucd" ]; then
        rm -rf "$HOME/.config/hucd"
        print_success "Removed legacy daemon config: ~/.config/hucd"
    fi
    if [ -d "$HOME/.local/share/hucd" ]; then
        rm -rf "$HOME/.local/share/hucd"
        print_success "Removed legacy daemon logs: ~/.local/share/hucd"
    fi

    # Remove nimble shims (if installed via nimble)
    local nimble_bin="$HOME/.nimble/bin"
    if [ -d "$nimble_bin" ]; then
        for shim in "huc" "hucd" "heads-up-claude"; do
            if [ -f "$nimble_bin/$shim" ]; then
                rm -f "$nimble_bin/$shim"
                print_success "Removed nimble shim: $nimble_bin/$shim"
            fi
        done
    fi

    print_success "Cleanup complete"
}

clear_all_config() {
    # Clear ALL config and settings for a fresh start
    local config_dir=$1
    echo ""
    print_step "Clearing all configuration for fresh install..."

    # Remove statusLine from settings.json
    local settings_file="$config_dir/settings.json"
    if [ -f "$settings_file" ]; then
        if grep -q "statusLine" "$settings_file" 2>/dev/null; then
            if command -v jq &> /dev/null; then
                local tmp_file=$(mktemp)
                jq 'del(.statusLine)' "$settings_file" > "$tmp_file" && mv "$tmp_file" "$settings_file"
                print_success "Removed statusLine from settings.json"
            else
                print_warning "jq not found - please manually remove statusLine from $settings_file"
            fi
        fi
    fi

    # Remove plan config file
    local plan_config="$config_dir/heads_up_config.json"
    if [ -f "$plan_config" ]; then
        rm -f "$plan_config"
        print_success "Removed plan config: $plan_config"
    fi

    # Remove legacy cache directory
    local cache_dir="$config_dir/heads-up-cache"
    if [ -d "$cache_dir" ]; then
        rm -rf "$cache_dir"
        print_success "Removed legacy cache directory: $cache_dir"
    fi

    # Remove legacy temp cache
    local legacy_cache="${TMPDIR:-/tmp}/heads-up-claude"
    if [ -d "$legacy_cache" ]; then
        rm -rf "$legacy_cache"
        print_success "Removed legacy cache: $legacy_cache"
    fi

    # Also check common alternate config dirs
    for alt_dir in "$HOME/.claude" "$HOME/.claude-work"; do
        if [ "$alt_dir" != "$config_dir" ]; then
            local alt_settings="$alt_dir/settings.json"
            if [ -f "$alt_settings" ] && grep -q "statusLine" "$alt_settings" 2>/dev/null; then
                if command -v jq &> /dev/null; then
                    local tmp_file=$(mktemp)
                    jq 'del(.statusLine)' "$alt_settings" > "$tmp_file" && mv "$tmp_file" "$alt_settings"
                    print_success "Removed statusLine from $alt_settings"
                fi
            fi

            local alt_cache="$alt_dir/heads-up-cache"
            if [ -d "$alt_cache" ]; then
                rm -rf "$alt_cache"
                print_success "Removed legacy cache: $alt_cache"
            fi

            local alt_config="$alt_dir/heads_up_config.json"
            if [ -f "$alt_config" ]; then
                rm -f "$alt_config"
                print_success "Removed plan config: $alt_config"
            fi
        fi
    done

    print_success "Configuration cleared"
}

check_nimble() {
    print_step "Checking for nimble command..."
    if command -v nimble &> /dev/null; then
        local version=$(nimble --version | head -n1)
        print_success "Found nimble: ${version}"
        return 0
    else
        print_warning "nimble command not found"
        return 1
    fi
}

detect_system() {
    print_step "Detecting system package manager..."

    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            print_success "Detected macOS with Homebrew"
            echo "brew"
        else
            print_warning "Detected macOS but Homebrew not found"
            echo "none"
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get &> /dev/null; then
            print_success "Detected Debian/Ubuntu (apt)"
            echo "apt"
        elif command -v dnf &> /dev/null; then
            print_success "Detected Fedora/RHEL (dnf)"
            echo "dnf"
        elif command -v yum &> /dev/null; then
            print_success "Detected CentOS/RHEL (yum)"
            echo "yum"
        elif command -v pacman &> /dev/null; then
            print_success "Detected Arch Linux (pacman)"
            echo "pacman"
        else
            print_warning "Linux detected but no known package manager found"
            echo "none"
        fi
    else
        print_warning "Unknown operating system: $OSTYPE"
        echo "none"
    fi
}

install_nimble() {
    local pkg_manager=$1

    echo ""
    print_step "nimble is required to build this project"
    print_info "Would you like to install it now?"
    echo ""
    read -p "Install nimble? [y/N] " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Installation cancelled"
        echo ""
        print_info "To install manually, visit: https://nim-lang.org/install.html"
        exit 1
    fi

    echo ""
    print_step "Installing nimble..."

    case $pkg_manager in
        brew)
            print_info "Running: brew install nim"
            if brew install nim; then
                print_success "Successfully installed nim and nimble via Homebrew"
            else
                print_error "Failed to install nim via Homebrew"
                exit 1
            fi
            ;;
        apt)
            print_info "Running: sudo apt-get update && sudo apt-get install nim"
            if sudo apt-get update && sudo apt-get install -y nim; then
                print_success "Successfully installed nim and nimble via apt"
            else
                print_error "Failed to install nim via apt"
                exit 1
            fi
            ;;
        dnf)
            print_info "Running: sudo dnf install nim"
            if sudo dnf install -y nim; then
                print_success "Successfully installed nim and nimble via dnf"
            else
                print_error "Failed to install nim via dnf"
                exit 1
            fi
            ;;
        yum)
            print_info "Running: sudo yum install nim"
            if sudo yum install -y nim; then
                print_success "Successfully installed nim and nimble via yum"
            else
                print_error "Failed to install nim via yum"
                exit 1
            fi
            ;;
        pacman)
            print_info "Running: sudo pacman -S nim"
            if sudo pacman -S --noconfirm nim; then
                print_success "Successfully installed nim and nimble via pacman"
            else
                print_error "Failed to install nim via pacman"
                exit 1
            fi
            ;;
        none)
            print_error "No supported package manager found"
            echo ""
            print_info "Please install nim manually from: https://nim-lang.org/install.html"
            exit 1
            ;;
    esac

    # Verify installation
    echo ""
    if command -v nimble &> /dev/null; then
        local version=$(nimble --version | head -n1)
        print_success "Verified nimble installation: ${version}"
    else
        print_error "nimble installation verification failed"
        exit 1
    fi
}

build_binary() {
    echo ""
    print_step "Installing dependencies..."
    echo ""

    nimble install -y

    echo ""
    print_step "Building huc (statusline)..."
    echo ""

    if ! nim c -d:release -o:/tmp/huc src/huc.nim; then
        echo ""
        print_error "huc build failed"
        exit 1
    fi

    print_success "huc (statusline) built"
}

install_binary() {
    echo ""
    print_step "Installing binary..."

    local bin_dir="$HOME/.local/bin"
    mkdir -p "$bin_dir"

    # Install huc
    cp /tmp/huc "$bin_dir/huc"
    chmod +x "$bin_dir/huc"
    print_success "Installed huc to $bin_dir/huc"

    # Create backward-compatible symlink: heads-up-claude -> huc
    ln -sf "$bin_dir/huc" "$bin_dir/heads-up-claude"
    print_success "Created symlink: heads-up-claude -> huc"

    # Clean up temp files
    rm -f /tmp/huc
}

run_statusline_installer() {
    local claude_config_dir=$1
    echo ""
    print_step "Configuring statusline..."
    echo ""

    local huc_bin="$HOME/.local/bin/huc"
    if [ -x "$huc_bin" ]; then
        if "$huc_bin" --install --claude-config-dir="$claude_config_dir"; then
            return 0
        else
            echo ""
            print_error "Statusline configuration failed"
            exit 1
        fi
    else
        print_error "huc binary not found at $huc_bin"
        exit 1
    fi
}


detect_claude_dirs() {
    echo ""
    print_step "Detecting Claude config directories..."
    echo ""

    # Search 1 level deep in $HOME for directories containing Claude markers
    local found_dirs=()

    for dir in "$HOME"/.*; do
        [ -d "$dir" ] || continue
        # Skip Trash directory (may contain deleted Claude files)
        [[ "$dir" == */.Trash ]] && continue

        # Check for Claude-specific markers (require multiple signals)
        local score=0
        [ -d "$dir/projects" ] && score=$((score + 2))  # Strong signal
        [ -f "$dir/settings.json" ] && grep -q '"env":\|"model":\|"statusLine":' "$dir/settings.json" 2>/dev/null && score=$((score + 2))
        [ -f "$dir/CLAUDE.md" ] && score=$((score + 1))

        # Require score >= 2 to be considered a Claude config dir
        if [ $score -ge 2 ]; then
            found_dirs+=("$dir")
        fi
    done

    if [ ${#found_dirs[@]} -eq 0 ]; then
        print_info "No existing Claude config directories detected"
        print_info "Using default: $CLAUDE_CONFIG_DIR"
        return
    fi

    print_success "Found ${#found_dirs[@]} Claude config director(ies):"
    echo ""

    # Display found directories with numbers
    local i=1
    for dir in "${found_dirs[@]}"; do
        local display_dir="${dir/#$HOME/\~}"
        echo "  $i) $display_dir"
        i=$((i + 1))
    done
    echo "  $i) Custom path"
    echo "  $((i + 1))) Use default (~/.claude)"
    echo ""

    # Prompt user to select
    local valid_input=false
    while [ "$valid_input" = false ]; do
        read -p "Select Claude config directory [1-$((i + 1))]: " selection

        if [[ "$selection" =~ ^[0-9]+$ ]]; then
            if [ "$selection" -ge 1 ] && [ "$selection" -le ${#found_dirs[@]} ]; then
                # User selected one of the found directories
                CLAUDE_CONFIG_DIR="${found_dirs[$((selection - 1))]}"
                print_success "Selected: ${CLAUDE_CONFIG_DIR/#$HOME/\~}"
                valid_input=true
            elif [ "$selection" -eq "$i" ]; then
                # User wants custom path
                echo ""
                read -p "Enter custom Claude config directory path: " custom_path
                # Expand tilde if present
                custom_path="${custom_path/#\~/$HOME}"
                if [ -n "$custom_path" ]; then
                    CLAUDE_CONFIG_DIR="$custom_path"
                    print_success "Using custom path: ${CLAUDE_CONFIG_DIR/#$HOME/\~}"
                    valid_input=true
                else
                    print_error "Invalid path"
                fi
            elif [ "$selection" -eq "$((i + 1))" ]; then
                # User wants default
                CLAUDE_CONFIG_DIR="$HOME/.claude"
                print_success "Using default: ~/.claude"
                valid_input=true
            else
                print_error "Invalid selection"
            fi
        else
            print_error "Please enter a number"
        fi
    done
    echo ""
}

print_completion() {
    local claude_config_dir=$1
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  Installation Complete!                                  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    print_success "Statusline binary: ~/.local/bin/huc"
    print_success "Backward-compat symlink: ~/.local/bin/heads-up-claude -> huc"
    print_success "Settings configured: $claude_config_dir/settings.json"
    echo ""
    print_info "Restart Claude Code to see the new statusline"
    echo ""
}

main() {
    # Parse command line arguments
    local skip_detection=false
    local clear_mode=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            --clear)
                clear_mode=true
                shift
                ;;
            --claude-config-dir=*)
                CLAUDE_CONFIG_DIR="${1#*=}"
                # Expand tilde if present
                CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR/#\~/$HOME}"
                skip_detection=true
                shift
                ;;
            --help|-h)
                print_help
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    print_header

    # Detect Claude config directories if not explicitly provided
    if [ "$skip_detection" = false ]; then
        detect_claude_dirs
    fi

    # If --clear flag was passed, clear all config before proceeding
    if [ "$clear_mode" = true ]; then
        clear_all_config "$CLAUDE_CONFIG_DIR"
    fi

    # Check for nimble
    if ! check_nimble; then
        # Detect system
        pkg_manager=$(detect_system)

        # Offer to install
        install_nimble "$pkg_manager"
    fi

    # Cleanup existing installation
    cleanup_all

    # Build binary
    build_binary

    # Install binary
    install_binary

    # Run the statusline installer (configures settings.json)
    run_statusline_installer "$CLAUDE_CONFIG_DIR"

    # Print completion
    print_completion "$CLAUDE_CONFIG_DIR"
}

# Run main function
main "$@"
