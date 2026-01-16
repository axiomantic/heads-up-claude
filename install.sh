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
    echo "  --claude-config-dir=PATH    Claude config directory"
    echo "                              If not specified, installer will auto-detect"
    echo "                              existing Claude directories and prompt for selection"
    echo "  --help, -h                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Auto-detect and prompt for selection"
    echo "  $0 --claude-config-dir=~/.claude-work # Install with specific config directory"
    echo ""
    echo "Auto-detection:"
    echo "  The installer searches for directories containing 'history.jsonl' or 'CLAUDE.md'"
    echo "  files in your home directory and prompts you to select which one to use."
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

    # Stop daemon - platform specific
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS: unload launchd plist
        local plist_path="$HOME/Library/LaunchAgents/com.headsup.claude.plist"
        if [ -f "$plist_path" ]; then
            print_step "Unloading launchd service..."
            launchctl unload "$plist_path" 2>/dev/null || true
            rm -f "$plist_path"
            print_success "Removed launchd plist"
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux: stop and disable systemd service
        local service_path="$HOME/.config/systemd/user/hucd.service"
        if [ -f "$service_path" ]; then
            print_step "Stopping systemd service..."
            systemctl --user stop hucd.service 2>/dev/null || true
            systemctl --user disable hucd.service 2>/dev/null || true
            rm -f "$service_path"
            systemctl --user daemon-reload 2>/dev/null || true
            print_success "Removed systemd service"
        fi
    fi

    # Kill orphaned processes
    print_step "Stopping any running processes..."
    pkill -9 -f "hucd" 2>/dev/null || true
    pkill -9 -f "heads-up-claude" 2>/dev/null || true
    sleep 1

    # Remove legacy files
    local legacy_files=(
        "$HOME/.local/bin/heads-up-claude"
        "$HOME/.local/bin/get_usage.exp"
    )
    for f in "${legacy_files[@]}"; do
        if [ -f "$f" ]; then
            rm -f "$f"
            print_success "Removed legacy file: $f"
        fi
    done

    # Remove new daemon files
    local daemon_files=(
        "$HOME/.local/bin/huc"
        "$HOME/.local/bin/hucd"
    )
    for f in "${daemon_files[@]}"; do
        if [ -f "$f" ]; then
            rm -f "$f"
            print_success "Removed: $f"
        fi
    done

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

build_binaries() {
    echo ""
    print_step "Installing dependencies..."
    echo ""

    nimble install -y

    echo ""
    print_step "Building huc (statusline)..."
    echo ""

    # Build huc (statusline binary)
    if ! nim c -d:release -o:/tmp/huc src/huc.nim; then
        echo ""
        print_error "huc build failed"
        exit 1
    fi

    print_success "huc (statusline) built"

    echo ""
    print_step "Building hucd (daemon)..."
    echo ""

    # Build hucd (daemon binary)
    if ! nim c -d:release -o:/tmp/hucd src/hucd.nim; then
        echo ""
        print_error "hucd build failed"
        exit 1
    fi

    print_success "hucd (daemon) built"
}

install_binaries() {
    echo ""
    print_step "Installing binaries..."

    local bin_dir="$HOME/.local/bin"
    mkdir -p "$bin_dir"

    # Install huc
    cp /tmp/huc "$bin_dir/huc"
    chmod +x "$bin_dir/huc"
    print_success "Installed huc to $bin_dir/huc"

    # Install hucd
    cp /tmp/hucd "$bin_dir/hucd"
    chmod +x "$bin_dir/hucd"
    print_success "Installed hucd to $bin_dir/hucd"

    # Create backward-compatible symlink: heads-up-claude -> huc
    ln -sf "$bin_dir/huc" "$bin_dir/heads-up-claude"
    print_success "Created symlink: heads-up-claude -> huc"

    # Clean up temp files
    rm -f /tmp/huc /tmp/hucd
}

create_daemon_config() {
    local claude_config_dir=$1
    echo ""
    print_step "Creating daemon configuration..."

    local cache_dir="$claude_config_dir/heads-up-cache"
    mkdir -p "$cache_dir"

    local config_path="$cache_dir/hucd.json"

    # Create default config
    cat > "$config_path" << EOF
{
  "version": 1,
  "config_dirs": ["$claude_config_dir"],
  "scan_interval_minutes": 5,
  "api_interval_minutes": 5,
  "prune_interval_minutes": 30,
  "debug": false
}
EOF

    print_success "Created daemon config: $config_path"
}

install_launchd() {
    local claude_config_dir=$1
    echo ""
    print_step "Installing launchd service (macOS)..."

    local plist_dir="$HOME/Library/LaunchAgents"
    local plist_path="$plist_dir/com.headsup.claude.plist"
    local bin_path="$HOME/.local/bin/hucd"
    local config_path="$claude_config_dir/heads-up-cache/hucd.json"
    local log_dir="$claude_config_dir/heads-up-cache/logs"

    mkdir -p "$plist_dir"
    mkdir -p "$log_dir"

    # Create plist
    cat > "$plist_path" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.headsup.claude</string>
    <key>ProgramArguments</key>
    <array>
        <string>$bin_path</string>
        <string>--config=$config_path</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$log_dir/hucd.out.log</string>
    <key>StandardErrorPath</key>
    <string>$log_dir/hucd.err.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>$HOME</string>
    </dict>
</dict>
</plist>
EOF

    print_success "Created launchd plist: $plist_path"

    # Load the service
    print_step "Loading launchd service..."
    launchctl unload "$plist_path" 2>/dev/null || true
    if launchctl load "$plist_path"; then
        print_success "launchd service loaded"
    else
        print_error "Failed to load launchd service"
        return 1
    fi
}

install_systemd() {
    local claude_config_dir=$1
    echo ""
    print_step "Installing systemd service (Linux)..."

    local service_dir="$HOME/.config/systemd/user"
    local service_path="$service_dir/hucd.service"
    local bin_path="$HOME/.local/bin/hucd"
    local config_path="$claude_config_dir/heads-up-cache/hucd.json"

    mkdir -p "$service_dir"

    # Create service file
    cat > "$service_path" << EOF
[Unit]
Description=Heads Up Claude Daemon
After=default.target

[Service]
Type=simple
ExecStart=$bin_path --config=$config_path
Restart=always
RestartSec=10
Environment=HOME=$HOME

[Install]
WantedBy=default.target
EOF

    print_success "Created systemd service: $service_path"

    # Reload and enable
    print_step "Enabling systemd service..."
    systemctl --user daemon-reload
    if systemctl --user enable hucd.service; then
        print_success "systemd service enabled"
    else
        print_error "Failed to enable systemd service"
        return 1
    fi

    # Start the service
    print_step "Starting systemd service..."
    if systemctl --user start hucd.service; then
        print_success "systemd service started"
    else
        print_error "Failed to start systemd service"
        return 1
    fi
}

install_service() {
    local claude_config_dir=$1
    echo ""
    print_step "Installing platform service..."

    if [[ "$OSTYPE" == "darwin"* ]]; then
        install_launchd "$claude_config_dir"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        install_systemd "$claude_config_dir"
    else
        print_warning "Unsupported platform for service installation: $OSTYPE"
        print_info "You will need to start hucd manually"
        return 1
    fi
}

wait_for_status() {
    local claude_config_dir=$1
    local status_path="$claude_config_dir/heads-up-cache/status.json"
    local timeout=30
    local elapsed=0

    echo ""
    print_step "Waiting for daemon to produce status..."

    while [ $elapsed -lt $timeout ]; do
        if [ -f "$status_path" ]; then
            print_success "Daemon is running and producing status"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    print_warning "Daemon did not produce status within ${timeout}s"
    print_info "Check logs at: $claude_config_dir/heads-up-cache/logs/"
    return 1
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

    # Find directories containing history.jsonl or CLAUDE.md
    # Search one level deep in home directory, including hidden directories
    local found_dirs=()

    # Use find to search for directories containing the marker files
    while IFS= read -r dir; do
        found_dirs+=("$dir")
    done < <(find "$HOME" -maxdepth 2 -type f \( -name "history.jsonl" -o -name "CLAUDE.md" \) -exec dirname {} \; 2>/dev/null | sort -u)

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
    print_success "Daemon binary: ~/.local/bin/hucd"
    print_success "Backward-compat symlink: ~/.local/bin/heads-up-claude -> huc"
    print_success "Settings configured: $claude_config_dir/settings.json"
    print_success "Daemon config: $claude_config_dir/heads-up-cache/hucd.json"
    echo ""
    print_info "The daemon (hucd) runs in the background to track usage"
    print_info "Restart Claude Code to see the new statusline"
    echo ""
}

main() {
    # Parse command line arguments
    local skip_detection=false
    while [[ $# -gt 0 ]]; do
        case $1 in
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

    # Check for nimble
    if ! check_nimble; then
        # Detect system
        pkg_manager=$(detect_system)

        # Offer to install
        install_nimble "$pkg_manager"
    fi

    # Cleanup existing installation
    cleanup_all

    # Build binaries
    build_binaries

    # Install binaries
    install_binaries

    # Create daemon configuration
    create_daemon_config "$CLAUDE_CONFIG_DIR"

    # Install platform service (launchd/systemd)
    install_service "$CLAUDE_CONFIG_DIR"

    # Wait for daemon to produce status
    wait_for_status "$CLAUDE_CONFIG_DIR"

    # Run the statusline installer (configures settings.json)
    run_statusline_installer "$CLAUDE_CONFIG_DIR"

    # Print completion
    print_completion "$CLAUDE_CONFIG_DIR"
}

# Run main function
main "$@"
