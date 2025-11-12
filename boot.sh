#!/bin/bash

# Vilo Quick Installer
# Downloads and runs the full Vilo installation script
# With GPU detection and distribution support

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Catch errors in pipes

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# ANSI art banner
ANSI_ART='
██╗   ██╗██╗██╗      ██████╗ 
██║   ██║██║██║     ██╔═══██╗
██║   ██║██║██║     ██║   ██║
╚██╗ ██╔╝██║██║     ██║   ██║
 ╚████╔╝ ██║███████╗╚██████╔╝
  ╚═══╝  ╚═╝╚══════╝ ╚═════╝ 
                                 
Hyprland Desktop Environment Installer
Powered by Ractor Package Manager
'

# Print functions
print_info() {
    echo -e "${BLUE}→${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_step() {
    echo -e "\n${CYAN}━━━ $1 ━━━${NC}"
}

# Error handler
error_exit() {
    print_error "$1"
    exit 1
}

# Cleanup function
cleanup() {
    if [ $? -ne 0 ]; then
        print_error "Installation failed. Please check the errors above."
        print_info "You can try running the installer again or report the issue at:"
        print_info "https://github.com/CyberHuman-bot/Vilo/issues"
    fi
}
trap cleanup EXIT

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    error_exit "This script should not be run as root. Please run as a normal user with sudo access."
fi

# GPU Detection Function
detect_gpu() {
    print_step "Detecting Graphics Card"
    
    GPU_TYPE="unknown"
    GPU_VENDOR=""
    GPU_MODEL=""
    
    # Try lspci first (most reliable)
    if command -v lspci &> /dev/null; then
        GPU_INFO=$(lspci | grep -i 'vga\|3d\|display' || true)
        
        if echo "$GPU_INFO" | grep -qi "nvidia"; then
            GPU_TYPE="nvidia"
            GPU_VENDOR="NVIDIA"
            GPU_MODEL=$(echo "$GPU_INFO" | grep -i nvidia | head -n1)
        elif echo "$GPU_INFO" | grep -qi "amd\|radeon"; then
            GPU_TYPE="amd"
            GPU_VENDOR="AMD"
            GPU_MODEL=$(echo "$GPU_INFO" | grep -iE "amd|radeon" | head -n1)
        elif echo "$GPU_INFO" | grep -qi "intel"; then
            GPU_TYPE="intel"
            GPU_VENDOR="Intel"
            GPU_MODEL=$(echo "$GPU_INFO" | grep -i intel | head -n1)
        fi
    fi
    
    # Fallback to checking loaded kernel modules
    if [ "$GPU_TYPE" = "unknown" ]; then
        if lsmod | grep -qi "nvidia"; then
            GPU_TYPE="nvidia"
            GPU_VENDOR="NVIDIA"
        elif lsmod | grep -qi "amdgpu"; then
            GPU_TYPE="amd"
            GPU_VENDOR="AMD"
        elif lsmod | grep -qi "i915\|xe"; then
            GPU_TYPE="intel"
            GPU_VENDOR="Intel"
        fi
    fi
    
    if [ "$GPU_TYPE" != "unknown" ]; then
        print_success "Detected GPU: $GPU_VENDOR"
        if [ -n "$GPU_MODEL" ]; then
            print_info "Model: $GPU_MODEL"
        fi
        
        # GPU-specific warnings
        if [ "$GPU_TYPE" = "nvidia" ]; then
            print_warning "NVIDIA GPU detected. Additional configuration will be applied."
            print_info "Note: NVIDIA on Wayland may require additional setup."
        fi
    else
        print_warning "Could not detect GPU type. Generic drivers will be used."
    fi
    
    echo ""
}

# Detect distribution
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO=$ID
        DISTRO_VERSION=${VERSION_ID:-unknown}
        DISTRO_LIKE=${ID_LIKE:-}
        DISTRO_NAME=${NAME:-$ID}
    elif [[ -f /etc/arch-release ]]; then
        DISTRO="arch"
        DISTRO_NAME="Arch Linux"
    elif [[ -f /etc/debian_version ]]; then
        DISTRO="debian"
        DISTRO_NAME="Debian"
    elif [[ -f /etc/fedora-release ]]; then
        DISTRO="fedora"
        DISTRO_NAME="Fedora"
    else
        error_exit "Unable to detect distribution"
    fi
}

# Initialize package manager based on distro
init_package_manager() {
    case "$DISTRO" in
        arch|manjaro|endeavouros|garuda|arcolinux|cachyos)
            PKG_MANAGER="pacman"
            PKG_INSTALL="sudo pacman -S --needed --noconfirm"
            PKG_UPDATE="sudo pacman -Sy"
            PACKAGES=(wget git curl pciutils)
            ;;
        debian|ubuntu|linuxmint|pop|elementary|zorin)
            PKG_MANAGER="apt"
            PKG_INSTALL="sudo apt-get install -y"
            PKG_UPDATE="sudo apt-get update"
            PACKAGES=(wget git curl pciutils)
            
            # Debian-specific warning
            if [[ "$DISTRO" == "debian" ]]; then
                DEBIAN_WARNING=true
            fi
            
            # Ubuntu version check
            if [[ "$DISTRO" == "ubuntu" ]]; then
                UBUNTU_VERSION="${DISTRO_VERSION%%.*}"
                if [[ "$UBUNTU_VERSION" -lt 24 ]]; then
                    UBUNTU_OLD_WARNING=true
                elif [[ "$UBUNTU_VERSION" -eq 24 ]] && [[ "${DISTRO_VERSION##*.}" -lt 10 ]]; then
                    UBUNTU_OLD_WARNING=true
                fi
            fi
            ;;
        fedora|rhel|centos|rocky|almalinux)
            PKG_MANAGER="dnf"
            PKG_INSTALL="sudo dnf install -y"
            PKG_UPDATE="sudo dnf check-update || true"
            PACKAGES=(wget git curl pciutils)
            ;;
        *)
            # Check ID_LIKE for derivative distros
            if [[ "$DISTRO_LIKE" == *"arch"* ]]; then
                PKG_MANAGER="pacman"
                PKG_INSTALL="sudo pacman -S --needed --noconfirm"
                PKG_UPDATE="sudo pacman -Sy"
                PACKAGES=(wget git curl pciutils)
            elif [[ "$DISTRO_LIKE" == *"debian"* ]] || [[ "$DISTRO_LIKE" == *"ubuntu"* ]]; then
                PKG_MANAGER="apt"
                PKG_INSTALL="sudo apt-get install -y"
                PKG_UPDATE="sudo apt-get update"
                PACKAGES=(wget git curl pciutils)
                if [[ "$DISTRO_LIKE" == *"debian"* ]]; then
                    DEBIAN_WARNING=true
                fi
            elif [[ "$DISTRO_LIKE" == *"fedora"* ]] || [[ "$DISTRO_LIKE" == *"rhel"* ]]; then
                PKG_MANAGER="dnf"
                PKG_INSTALL="sudo dnf install -y"
                PKG_UPDATE="sudo dnf check-update || true"
                PACKAGES=(wget git curl pciutils)
            else
                error_exit "Unsupported distribution: $DISTRO. Supported: Arch, Debian, Ubuntu, Fedora, and derivatives"
            fi
            ;;
    esac
}

# System requirements check
check_system_requirements() {
    print_step "Checking System Requirements"
    
    # Check CPU architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" != "x86_64" ]]; then
        print_warning "Non-x86_64 architecture detected: $ARCH"
        print_info "Vilo is optimized for x86_64 systems"
    else
        print_success "Architecture: $ARCH"
    fi
    
    # Check available RAM
    TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    if [[ $TOTAL_RAM -lt 2048 ]]; then
        print_warning "Low RAM detected: ${TOTAL_RAM}MB (2GB minimum recommended)"
    else
        print_success "RAM: ${TOTAL_RAM}MB"
    fi
    
    # Check available disk space
    AVAILABLE_SPACE=$(df -m / | awk 'NR==2 {print $4}')
    if [[ $AVAILABLE_SPACE -lt 20480 ]]; then
        print_warning "Low disk space: ${AVAILABLE_SPACE}MB available (20GB recommended)"
    else
        print_success "Disk space: ${AVAILABLE_SPACE}MB available"
    fi
    
    # Check internet connectivity
    if ping -c 1 -W 2 8.8.8.8 &> /dev/null; then
        print_success "Internet connection: Available"
    else
        error_exit "No internet connection detected. Please connect to the internet and try again."
    fi
    
    echo ""
}

# Display welcome banner
clear
echo -e "${BLUE}${ANSI_ART}${NC}"

# Detect distribution
print_info "Detecting system configuration..."
detect_distro
init_package_manager
print_success "Detected: $DISTRO_NAME (using $PKG_MANAGER)"
echo ""

# Detect GPU
detect_gpu

# Check system requirements
check_system_requirements

# Show warnings if needed
if [[ "${DEBIAN_WARNING:-false}" == "true" ]]; then
    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║               ⚠  IMPORTANT NOTICE  ⚠                     ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}"
    echo "  Debian's Hyprland packages are extremely outdated."
    echo "  You may experience:"
    echo "    • Installation difficulties"
    echo "    • Missing packages in official repositories"
    echo "    • Potential compatibility issues"
    echo ""
    echo "  Recommended: Use Arch Linux or Fedora 40+ for best experience."
    echo -e "${NC}"
    read -p "Do you want to continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Installation cancelled by user"
        exit 0
    fi
    echo ""
fi

if [[ "${UBUNTU_OLD_WARNING:-false}" == "true" ]]; then
    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║               ⚠  UBUNTU VERSION NOTICE  ⚠                ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}"
    echo "  Ubuntu $DISTRO_VERSION detected."
    echo "  Hyprland packages may be outdated or require building from source."
    echo ""
    echo "  Recommended: Ubuntu 24.10+, Arch Linux, or Fedora 40+"
    echo -e "${NC}"
    read -p "Continue with installation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Installation cancelled by user"
        exit 0
    fi
    echo ""
fi

# Show what will be installed
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}       Vilo Installation Summary        ${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}This installer will:${NC}"
echo "  • Install Hyprland (Wayland compositor)"
echo "  • Install Waybar (Status bar)"
echo "  • Install Walker/Rofi (Application launcher)"
echo "  • Install essential utilities and dependencies"
echo "  • Apply GPU-optimized settings for $GPU_VENDOR"
echo "  • Configure your desktop environment"
echo ""
echo -e "${BLUE}System Information:${NC}"
echo "  • Distribution: $DISTRO_NAME"
echo "  • Package Manager: $PKG_MANAGER"
echo "  • Graphics: $GPU_VENDOR ${GPU_TYPE}"
echo "  • Architecture: $ARCH"
echo ""

# Confirm installation
read -p "Continue with installation? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Installation cancelled by user"
    exit 0
fi

# Initialize pacman keyring if needed
if [[ "$PKG_MANAGER" == "pacman" ]]; then
    print_step "Initializing Package Manager"
    print_info "Setting up pacman keyring..."
    sudo pacman-key --init 2>/dev/null || print_warning "Keyring already initialized"
    sudo pacman-key --populate archlinux 2>/dev/null || true
    print_success "Package manager ready"
fi

# Update package database
print_step "Updating Package Database"
print_info "This may take a moment..."
eval "$PKG_UPDATE" || print_warning "Package database update had warnings (continuing...)"
print_success "Package database updated"

# Install dependencies
print_step "Installing Bootstrap Dependencies"
for pkg in "${PACKAGES[@]}"; do
    print_info "Installing $pkg..."
    eval "$PKG_INSTALL $pkg" || error_exit "Failed to install $pkg"
done
print_success "All bootstrap dependencies installed"

RACTOR_URL="https://raw.githubusercontent.com/CyberHuman-bot/Ractor/refs/heads/main/ractor.sh"
print_step "Downloading Ractor..."
if wget -q --spider "$RACTOR_URL"; then
  wget -q -O /tmp/ractor.sh "$RACTOR_URL" || print_error "Failed to download Ractor"
  chmod +x /tmp/ractor.sh
  sudo mv /tmp/ractor.sh /usr/local/bin/ractor || print_error "Failed to install Ractor"
  print_success "Ractor installed successfully"
else
  print_warning "Ractor download failed (non-critical, continuing...)"
fi

# Download and run main installation script
print_step "Downloading Vilo Installation Script"

VILO_REPO="${VILO_REPO:-CyberHuman-bot/Vilo}"
VILO_REF="${VILO_REF:-main}"
VILO_SCRIPT_URL="https://raw.githubusercontent.com/${VILO_REPO}/${VILO_REF}/install.sh"

print_info "Fetching from: ${VILO_REPO} (${VILO_REF})"

# Download the installation script
TEMP_SCRIPT=$(mktemp)
if wget -q -O "$TEMP_SCRIPT" "$VILO_SCRIPT_URL"; then
    print_success "Installation script downloaded"
else
    error_exit "Failed to download Vilo installation script from $VILO_SCRIPT_URL"
fi

# Make it executable
chmod +x "$TEMP_SCRIPT"

# Export GPU information for the main script
export VILO_GPU_TYPE="$GPU_TYPE"
export VILO_GPU_VENDOR="$GPU_VENDOR"
export VILO_DISTRO="$DISTRO"
export VILO_PKG_MANAGER="$PKG_MANAGER"

# Run the main installation script
print_step "Running Vilo Installation Script"
echo ""

if bash "$TEMP_SCRIPT"; then
    rm -f "$TEMP_SCRIPT"
    
    # Success message
    clear
    echo -e "${GREEN}"
    cat << 'EOF'
╔═══════════════════════════════════════╗
║     Vilo Installation Complete!       ║
╚═══════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    echo -e "${CYAN}Installation Summary:${NC}"
    print_success "Hyprland environment installed"
    print_success "GPU optimizations applied ($GPU_VENDOR)"
    print_success "All configurations complete"
    echo ""
    
    echo -e "${BLUE}Next Steps:${NC}"
    echo "  1. Reboot your system: ${CYAN}sudo reboot${NC}"
    echo "  2. Select 'Hyprland' at login screen"
    echo "  3. Press ${CYAN}SUPER + RETURN${NC} to open terminal"
    echo "  4. Press ${CYAN}SUPER + R${NC} to open app launcher"
    echo ""
    
    echo -e "${YELLOW}Quick Keybindings:${NC}"
    echo "  SUPER + RETURN       → Terminal"
    echo "  SUPER + R            → App Launcher"
    echo "  SUPER + Q            → Close Window"
    echo "  SUPER + E            → File Manager"
    echo "  SUPER + F            → Fullscreen"
    echo "  SUPER + 1-9          → Switch Workspace"
    echo ""
    
    echo -e "${MAGENTA}Join Our Community:${NC}"
    echo "  Discord: https://discord.gg/6naeNfwEtY"
    echo "  GitHub:  https://github.com/CyberHuman-bot/Vilo"
    echo ""
    
    print_success "Installation completed successfully!"
    echo ""
    
    read -p "Press Enter to exit..."
else
    rm -f "$TEMP_SCRIPT"
    error_exit "Installation script failed. Please check the errors above."
fi
