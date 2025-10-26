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

run_installer() {
    echo ""
    print_step "Building heads-up-claude..."
    echo ""

    # Build release binary
    if ! nim c -d:release --hints:off --warnings:off -o:/tmp/heads-up-claude src/heads_up_claude.nim > /dev/null 2>&1; then
        print_error "Build failed"
        exit 1
    fi

    print_success "Build complete"
    echo ""
    print_step "Starting installation..."
    echo ""

    if /tmp/heads-up-claude --install; then
        rm -f /tmp/heads-up-claude
        return 0
    else
        rm -f /tmp/heads-up-claude
        echo ""
        print_error "Installation failed"
        exit 1
    fi
}

print_completion() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  Installation Complete!                                  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    print_success "Binary installed to: ~/.local/bin/heads-up-claude"
    echo ""
}

main() {
    print_header

    # Check for nimble
    if ! check_nimble; then
        # Detect system
        pkg_manager=$(detect_system)

        # Offer to install
        install_nimble "$pkg_manager"
    fi

    # Run the installer (which will build and install)
    if run_installer; then
        # Print completion message only if installer succeeded
        print_completion
    fi
}

# Run main function
main
