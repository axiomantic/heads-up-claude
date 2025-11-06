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
    print_step "Building statusline binary..."
    echo ""

    # Build statusline binary - show all output
    if ! nim c -d:release -o:/tmp/heads-up-claude src/heads_up_claude.nim; then
        echo ""
        print_error "Statusline build failed"
        exit 1
    fi

    print_success "Statusline binary built"

    # Copy expect script to tmp for installation
    echo ""
    print_step "Copying usage data script..."
    if [ -f "$SCRIPT_DIR/get_usage.exp" ]; then
        cp "$SCRIPT_DIR/get_usage.exp" /tmp/get_usage.exp
        chmod +x /tmp/get_usage.exp
        print_success "Usage data script prepared"
    else
        print_warning "get_usage.exp not found - usage data may be limited"
    fi
}


run_statusline_installer() {
    local claude_config_dir=$1
    echo ""
    print_step "Configuring statusline..."
    echo ""

    if /tmp/heads-up-claude --install --claude-config-dir="$claude_config_dir"; then
        rm -f /tmp/heads-up-claude
        return 0
    else
        rm -f /tmp/heads-up-claude
        echo ""
        print_error "Statusline configuration failed"
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
    print_success "Statusline binary: ~/.local/bin/heads-up-claude"
    print_success "Settings configured: $claude_config_dir/settings.json"
    echo ""
    print_info "Usage estimates are based on local conversation activity"
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

    # Build binary
    build_binaries

    # Run the statusline installer
    run_statusline_installer "$CLAUDE_CONFIG_DIR"

    # Print completion
    print_completion "$CLAUDE_CONFIG_DIR"
}

# Run main function
main "$@"
