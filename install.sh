#!/bin/bash

# Vilo Installation Script
# Installs and configures Hyprland + Waybar + Walker
# With automatic GPU detection and optimization

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
    fi
}
trap cleanup EXIT

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    error_exit "Please do not run this script as root"
fi

# GPU Detection Function
detect_gpu() {
    print_step "Detecting Graphics Card"
    
    GPU_TYPE="unknown"
    GPU_VENDOR=""
    GPU_MODEL=""
    
    # Try lspci first (most reliable)
    if command -v lspci &> /dev/null; then
        GPU_INFO=$(lspci | grep -i 'vga\|3d\|display')
        
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
    else
        print_warning "Could not detect GPU type. Using default settings."
    fi
    
    echo ""
}

# Install GPU-specific packages
install_gpu_drivers() {
    print_step "Installing GPU-Specific Packages"
    
    case "$GPU_TYPE" in
        nvidia)
            print_info "Installing NVIDIA packages..."
            if [[ "$PKG_MANAGER" == "pacman" ]]; then
                GPU_PKGS=(
                    nvidia
                    nvidia-utils
                    nvidia-settings
                    libva-nvidia-driver
                )
            elif [[ "$PKG_MANAGER" == "apt" ]]; then
                GPU_PKGS=(
                    nvidia-driver
                    nvidia-settings
                    libnvidia-gl-550
                    libva-nvidia-driver
                )
            elif [[ "$PKG_MANAGER" == "dnf" ]]; then
                # Enable RPM Fusion for NVIDIA drivers
                print_info "Enabling RPM Fusion repositories..."
                sudo dnf install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm || true
                sudo dnf install -y https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm || true
                
                GPU_PKGS=(
                    akmod-nvidia
                    xorg-x11-drv-nvidia-cuda
                    nvidia-settings
                )
            fi
            
            for pkg in "${GPU_PKGS[@]}"; do
                eval "$PKG_INSTALL $pkg" || print_warning "Failed to install $pkg"
            done
            
            print_warning "NVIDIA GPU detected. Additional configuration may be required."
            print_info "Please refer to: https://wiki.hyprland.org/Nvidia/"
            ;;
            
        amd)
            print_info "Installing AMD packages..."
            if [[ "$PKG_MANAGER" == "pacman" ]]; then
                GPU_PKGS=(
                    mesa
                    lib32-mesa
                    vulkan-radeon
                    lib32-vulkan-radeon
                    libva-mesa-driver
                    lib32-libva-mesa-driver
                    mesa-vdpau
                    lib32-mesa-vdpau
                )
            elif [[ "$PKG_MANAGER" == "apt" ]]; then
                GPU_PKGS=(
                    mesa-vulkan-drivers
                    libva-mesa-driver
                    mesa-vdpau-drivers
                )
            elif [[ "$PKG_MANAGER" == "dnf" ]]; then
                GPU_PKGS=(
                    mesa-dri-drivers
                    mesa-vulkan-drivers
                    mesa-va-drivers
                    mesa-vdpau-drivers
                )
            fi
            
            for pkg in "${GPU_PKGS[@]}"; do
                eval "$PKG_INSTALL $pkg" || print_warning "Failed to install $pkg"
            done
            
            print_success "AMD GPU packages installed"
            ;;
            
        intel)
            print_info "Installing Intel packages..."
            if [[ "$PKG_MANAGER" == "pacman" ]]; then
                GPU_PKGS=(
                    mesa
                    lib32-mesa
                    vulkan-intel
                    lib32-vulkan-intel
                    intel-media-driver
                    libva-intel-driver
                )
            elif [[ "$PKG_MANAGER" == "apt" ]]; then
                GPU_PKGS=(
                    mesa-vulkan-drivers
                    intel-media-va-driver
                    i965-va-driver
                )
            elif [[ "$PKG_MANAGER" == "dnf" ]]; then
                GPU_PKGS=(
                    mesa-dri-drivers
                    mesa-vulkan-drivers
                    intel-media-driver
                    libva-intel-driver
                )
            fi
            
            for pkg in "${GPU_PKGS[@]}"; do
                eval "$PKG_INSTALL $pkg" || print_warning "Failed to install $pkg"
            done
            
            print_success "Intel GPU packages installed"
            ;;
            
        *)
            print_warning "Unknown GPU type. Installing generic Mesa drivers..."
            if [[ "$PKG_MANAGER" == "pacman" ]]; then
                eval "$PKG_INSTALL mesa vulkan-icd-loader" || true
            elif [[ "$PKG_MANAGER" == "apt" ]]; then
                eval "$PKG_INSTALL mesa-vulkan-drivers" || true
            elif [[ "$PKG_MANAGER" == "dnf" ]]; then
                eval "$PKG_INSTALL mesa-vulkan-drivers" || true
            fi
            ;;
    esac
}

# Generate GPU-optimized Hyprland config
generate_gpu_env_vars() {
    case "$GPU_TYPE" in
        nvidia)
            cat << 'EOF'
# NVIDIA-specific environment variables
env = LIBVA_DRIVER_NAME,nvidia
env = XDG_SESSION_TYPE,wayland
env = GBM_BACKEND,nvidia-drm
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = WLR_NO_HARDWARE_CURSORS,1
env = ELECTRON_OZONE_PLATFORM_HINT,auto

# NVIDIA cursor fix
cursor {
    no_hardware_cursors = true
}
EOF
            ;;
            
        amd)
            cat << 'EOF'
# AMD-specific environment variables
env = LIBVA_DRIVER_NAME,radeonsi
env = VDPAU_DRIVER,radeonsi
env = AMD_VULKAN_ICD,RADV
env = RADV_PERFTEST,gpl
EOF
            ;;
            
        intel)
            cat << 'EOF'
# Intel-specific environment variables
env = LIBVA_DRIVER_NAME,iHD
env = VDPAU_DRIVER,va_gl
EOF
            ;;
            
        *)
            cat << 'EOF'
# Generic environment variables
EOF
            ;;
    esac
}

# Generate GPU-optimized rendering settings
generate_gpu_render_settings() {
    case "$GPU_TYPE" in
        nvidia)
            cat << 'EOF'
# NVIDIA rendering optimizations
render {
    explicit_sync = 2
    explicit_sync_kms = 2
    direct_scanout = false
}

# Reduce tearing on NVIDIA
misc {
    vrr = 1
    vfr = true
}
EOF
            ;;
            
        amd)
            cat << 'EOF'
# AMD rendering optimizations
render {
    explicit_sync = 1
    direct_scanout = true
}

misc {
    vrr = 2
    vfr = true
}
EOF
            ;;
            
        intel)
            cat << 'EOF'
# Intel rendering optimizations
render {
    explicit_sync = 1
    direct_scanout = true
}

misc {
    vrr = 0
    vfr = true
}
EOF
            ;;
            
        *)
            cat << 'EOF'
# Default rendering settings
render {
    explicit_sync = 1
}
EOF
            ;;
    esac
}

# Detect distribution
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO=$ID
        DISTRO_LIKE=${ID_LIKE:-}
    elif [[ -f /etc/arch-release ]]; then
        DISTRO="arch"
    elif [[ -f /etc/debian_version ]]; then
        DISTRO="debian"
    elif [[ -f /etc/fedora-release ]]; then
        DISTRO="fedora"
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
            PKG_UPDATE="sudo pacman -Syu --noconfirm"
            AUR_HELPER="yay"
            ;;
        debian|ubuntu|linuxmint|pop)
            PKG_MANAGER="apt"
            PKG_INSTALL="sudo apt-get install -y"
            PKG_UPDATE="sudo apt-get update && sudo apt-get upgrade -y"
            AUR_HELPER=""
            if [[ "$DISTRO" == "debian" ]]; then
                DEBIAN_HYPRLAND_WARNING=true
            fi
            ;;
        fedora|rhel|centos|rocky|almalinux)
            PKG_MANAGER="dnf"
            PKG_INSTALL="sudo dnf install -y"
            PKG_UPDATE="sudo dnf upgrade -y"
            AUR_HELPER=""
            ;;
        *)
            if [[ "$DISTRO_LIKE" == *"arch"* ]]; then
                PKG_MANAGER="pacman"
                PKG_INSTALL="sudo pacman -S --needed --noconfirm"
                PKG_UPDATE="sudo pacman -Syu --noconfirm"
                AUR_HELPER="yay"
            elif [[ "$DISTRO_LIKE" == *"debian"* ]] || [[ "$DISTRO_LIKE" == *"ubuntu"* ]]; then
                PKG_MANAGER="apt"
                PKG_INSTALL="sudo apt-get install -y"
                PKG_UPDATE="sudo apt-get update && sudo apt-get upgrade -y"
                AUR_HELPER=""
                if [[ "$DISTRO_LIKE" == *"debian"* ]]; then
                    DEBIAN_HYPRLAND_WARNING=true
                fi
            elif [[ "$DISTRO_LIKE" == *"fedora"* ]] || [[ "$DISTRO_LIKE" == *"rhel"* ]]; then
                PKG_MANAGER="dnf"
                PKG_INSTALL="sudo dnf install -y"
                PKG_UPDATE="sudo dnf upgrade -y"
                AUR_HELPER=""
            else
                error_exit "Unsupported distribution: $DISTRO. Supported: Arch, Debian, Ubuntu, Fedora, and derivatives"
            fi
            ;;
    esac
}

# Welcome banner
clear
echo -e "${BLUE}"
cat << 'EOF'
╔═══════════════════════════════════════╗
║          Vilo Installation            ║
║       Hyprland + Waybar + Walker      ║
║        with GPU Auto-Detection        ║
╚═══════════════════════════════════════╝
EOF
echo -e "${NC}"

# Detect distribution
print_info "Detecting distribution..."
detect_distro
init_package_manager
print_success "Detected: $DISTRO (using $PKG_MANAGER)"
echo ""

# Detect GPU early
detect_gpu

# Debian Hyprland warning
if [[ "${DEBIAN_HYPRLAND_WARNING:-false}" == "true" ]]; then
    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║               ⚠  IMPORTANT NOTICE  ⚠                     ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}"
    echo "  Hyprland does not have 100% official support on Debian."
    echo "  You may experience:"
    echo "    • Installation difficulties"
    echo "    • Missing packages in official repositories"
    echo "    • Potential compatibility issues"
    echo ""
    echo "  Recommended: Use Arch, Fedora, or Ubuntu for better support."
    echo -e "${NC}"
    read -p "Do you want to continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Installation cancelled by user"
        exit 0
    fi
    echo ""
fi

# Show what will be installed
echo -e "${CYAN}This script will install:${NC}"
echo "  • Hyprland (Wayland compositor)"
echo "  • Waybar (Status bar)"
echo "  • Walker (Application launcher)"
echo "  • Essential utilities and dependencies"
echo "  • GPU-optimized settings for $GPU_VENDOR"
echo ""

# Confirm installation
read -p "Continue with installation? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Installation cancelled by user"
    exit 0
fi

# Update system
print_step "System Update"
print_info "Updating system packages..."
eval "$PKG_UPDATE" || error_exit "Failed to update system"
print_success "System updated"

# Install base dependencies
print_step "Installing Base Dependencies"

if [[ "$PKG_MANAGER" == "pacman" ]]; then
    BASE_DEPS=(
        base-devel
        git
        wget
        curl
        pciutils
    )
elif [[ "$PKG_MANAGER" == "apt" ]]; then
    BASE_DEPS=(
        build-essential
        git
        wget
        curl
        meson
        cmake
        ninja-build
        pkg-config
        pciutils
    )
elif [[ "$PKG_MANAGER" == "dnf" ]]; then
    BASE_DEPS=(
        gcc
        gcc-c++
        git
        wget
        curl
        meson
        cmake
        ninja-build
        pkgconfig
        pciutils
    )
fi

for dep in "${BASE_DEPS[@]}"; do
    print_info "Installing $dep..."
    eval "$PKG_INSTALL $dep" || print_warning "Failed to install $dep (continuing...)"
done
print_success "Base dependencies installed"

# Install GPU-specific drivers
install_gpu_drivers

# Install Hyprland and related packages
print_step "Installing Hyprland Environment"

if [[ "$PKG_MANAGER" == "pacman" ]]; then
    HYPRLAND_PKGS=(
        hyprland
        xdg-desktop-portal-hyprland
        qt5-wayland
        qt6-wayland
        polkit-kde-agent
        kitty
        dunst
        rofi-wayland
        swww
        grim
        slurp
        wl-clipboard
        cliphist
        brightnessctl
        playerctl
        pavucontrol
        network-manager-applet
        bluez
        bluez-utils
        blueman
        thunar
        pipewire
        pipewire-pulse
        wireplumber
    )
elif [[ "$PKG_MANAGER" == "apt" ]]; then
    if [[ "$DISTRO" == "debian" ]]; then
        print_info "Enabling backports repository..."
        echo "deb http://deb.debian.org/debian $(lsb_release -sc)-backports main" | sudo tee /etc/apt/sources.list.d/backports.list || true
        sudo apt-get update || true
    fi
    
    HYPRLAND_PKGS=(
        kitty
        dunst
        rofi
        grim
        slurp
        wl-clipboard
        brightnessctl
        playerctl
        pavucontrol
        network-manager-gnome
        bluez
        blueman
        thunar
        pipewire
        pipewire-pulse
        wireplumber
        libwayland-dev
        wayland-protocols
        libxkbcommon-dev
        libegl-dev
        libgles-dev
        libdrm-dev
        libgbm-dev
        libinput-dev
        libxcb-composite0-dev
        libxcb-xfixes0-dev
        libxcb-xinput-dev
        libxcb-image0-dev
        libxcb-render-util0-dev
        libxcb-ewmh-dev
        libxcb-icccm4-dev
        libpango1.0-dev
        libcairo2-dev
    )
elif [[ "$PKG_MANAGER" == "dnf" ]]; then
    HYPRLAND_PKGS=(
        hyprland
        xdg-desktop-portal-hyprland
        qt5-qtwayland
        qt6-qtwayland
        polkit-kde
        kitty
        dunst
        rofi-wayland
        grim
        slurp
        wl-clipboard
        brightnessctl
        playerctl
        pavucontrol
        network-manager-applet
        bluez
        blueman
        thunar
        pipewire
        pipewire-pulseaudio
        wireplumber
    )
fi

print_info "Installing Hyprland packages (${#HYPRLAND_PKGS[@]} packages)..."
for pkg in "${HYPRLAND_PKGS[@]}"; do
    eval "$PKG_INSTALL $pkg" || print_warning "Failed to install $pkg (continuing...)"
done
print_success "Hyprland environment installed"

# Special handling for Hyprland on Debian/Ubuntu
if [[ "$PKG_MANAGER" == "apt" ]] && ! command -v Hyprland &> /dev/null; then
    print_warning "Hyprland not found in repositories. Attempting to build from source..."
    print_info "This may take several minutes..."
    
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    if git clone --recursive https://github.com/hyprwm/Hyprland; then
        cd Hyprland
        make all && sudo make install || print_warning "Hyprland build failed. You may need to install it manually."
        cd "$HOME"
    else
        print_warning "Failed to clone Hyprland. You'll need to install it manually."
    fi
    
    rm -rf "$TEMP_DIR"
fi

# Install Waybar
print_step "Installing Waybar"

if [[ "$PKG_MANAGER" == "pacman" ]]; then
    WAYBAR_PKGS=(
        waybar
        otf-font-awesome
        ttf-jetbrains-mono-nerd
        ttf-firacode-nerd
    )
elif [[ "$PKG_MANAGER" == "apt" ]]; then
    WAYBAR_PKGS=(
        waybar
        fonts-font-awesome
        fonts-noto
    )
    print_info "Installing Nerd Fonts..."
    mkdir -p ~/.local/share/fonts
    cd ~/.local/share/fonts
    wget -q https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/JetBrainsMono.zip || true
    if [[ -f JetBrainsMono.zip ]]; then
        unzip -q -o JetBrainsMono.zip
        rm JetBrainsMono.zip
        fc-cache -f
    fi
    cd "$HOME"
elif [[ "$PKG_MANAGER" == "dnf" ]]; then
    WAYBAR_PKGS=(
        waybar
        fontawesome-fonts
        jetbrains-mono-fonts
    )
fi

print_info "Installing Waybar and fonts..."
for pkg in "${WAYBAR_PKGS[@]}"; do
    eval "$PKG_INSTALL $pkg" || print_warning "Failed to install $pkg (continuing...)"
done
print_success "Waybar installed"

# Install AUR helper (Arch only)
if [[ "$PKG_MANAGER" == "pacman" ]]; then
    print_step "Setting Up AUR Helper"
    if ! command -v yay &> /dev/null; then
        print_info "Installing yay AUR helper..."
        TEMP_DIR=$(mktemp -d)
        cd "$TEMP_DIR"
        git clone https://aur.archlinux.org/yay.git || error_exit "Failed to clone yay repository"
        cd yay
        makepkg -si --noconfirm || error_exit "Failed to install yay"
        cd "$HOME"
        rm -rf "$TEMP_DIR"
        print_success "yay installed"
    else
        print_success "yay already installed"
    fi
fi

# Install Walker
print_step "Installing Walker"

if [[ "$PKG_MANAGER" == "pacman" ]]; then
    print_info "Installing Walker from AUR..."
    yay -S --needed --noconfirm walker-git || yay -S --needed --noconfirm walker || print_warning "Failed to install Walker. You may need to install it manually."
elif [[ "$PKG_MANAGER" == "apt" ]]; then
    print_warning "Walker not available in apt repositories."
    print_info "You can install it from: https://github.com/abenz1267/walker"
    print_info "Alternatively, rofi will be used as a fallback launcher."
elif [[ "$PKG_MANAGER" == "dnf" ]]; then
    print_warning "Walker not available in dnf repositories."
    print_info "You can install it from: https://github.com/abenz1267/walker"
    print_info "Alternatively, rofi will be used as a fallback launcher."
fi

# Install swww for wallpapers (if not already installed)
if ! command -v swww &> /dev/null; then
    print_info "Installing swww for wallpaper management..."
    if [[ "$PKG_MANAGER" == "pacman" ]]; then
        eval "$PKG_INSTALL swww" || print_warning "Failed to install swww"
    else
        print_warning "swww not available. You may need to install it manually from: https://github.com/Horus645/swww"
    fi
fi

# Enable services
print_step "Enabling System Services"
print_info "Enabling Bluetooth service..."
sudo systemctl enable bluetooth.service 2>/dev/null || print_warning "Failed to enable Bluetooth (non-critical)"
print_success "Services configured"

# Create config directories
print_step "Creating Configuration Directories"
CONFIG_DIRS=(
    "$HOME/.config/hypr"
    "$HOME/.config/waybar"
    "$HOME/.config/walker"
    "$HOME/.config/kitty"
    "$HOME/.config/dunst"
)

for dir in "${CONFIG_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        print_info "Created $dir"
    fi
done
print_success "Configuration directories ready"

# Backup existing configs
print_step "Backing Up Existing Configurations"
for dir in "${CONFIG_DIRS[@]}"; do
    config_name=$(basename "$dir")
    if [ -d "$dir" ] && [ "$(ls -A "$dir" 2>/dev/null)" ]; then
        backup_dir="${dir}.backup.$(date +%Y%m%d_%H%M%S)"
        cp -r "$dir" "$backup_dir"
        print_info "Backed up $config_name to $backup_dir"
    fi
done

# Configure Hyprland with GPU optimizations
print_step "Configuring Hyprland with GPU Optimizations"
print_info "Writing GPU-optimized Hyprland configuration for $GPU_VENDOR..."

# Determine launcher command based on what's available
if command -v walker &> /dev/null; then
    LAUNCHER_CMD="walker"
elif command -v rofi &> /dev/null; then
    LAUNCHER_CMD="rofi -show drun"
else
    LAUNCHER_CMD="wofi --show drun"
fi

cat > ~/.config/hypr/hyprland.conf << EOF
# Vilo Hyprland Configuration
# GPU: $GPU_VENDOR ($GPU_TYPE)

# Monitor configuration
monitor=,preferred,auto,1

# Execute at launch
exec-once = waybar
exec-once = dunst
exec-once = /usr/lib/polkit-kde-authentication-agent-1
exec-once = swww init || true
exec-once = nm-applet --indicator
exec-once = blueman-applet
exec-once = wl-paste --type text --watch cliphist store
exec-once = wl-paste --type image --watch cliphist store

# Common environment variables
env = XCURSOR_SIZE,24
env = QT_QPA_PLATFORMTHEME,qt5ct
env = QT_QPA_PLATFORM,wayland
env = GDK_BACKEND,wayland
env = XDG_CURRENT_DESKTOP,Hyprland
env = XDG_SESSION_TYPE,wayland
env = XDG_SESSION_DESKTOP,Hyprland

$(generate_gpu_env_vars)

# Input configuration
input {
    kb_layout = us
    follow_mouse = 1
    touchpad {
        natural_scroll = true
        disable_while_typing = true
        tap-to-click = true
    }
    sensitivity = 0
    accel_profile = flat
}

# General settings
general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
    col.inactive_border = rgba(595959aa)
    layout = dwindle
    allow_tearing = false
}

# Decoration
decoration {
    rounding = 10
    blur {
        enabled = true
        size = 3
        passes = 1
        vibrancy = 0.1696
    }
    drop_shadow = true
    shadow_range = 4
    shadow_render_power = 3
    col.shadow = rgba(1a1a1aee)
}

# Animations
animations {
    enabled = true
    bezier = myBezier, 0.05, 0.9, 0.1, 1.05
    animation = windows, 1, 7, myBezier
    animation = windowsOut, 1, 7, default, popin 80%
    animation = border, 1, 10, default
    animation = borderangle, 1, 8, default
    animation = fade, 1, 7, default
    animation = workspaces, 1, 6, default
}

# Layouts
dwindle {
    pseudotile = true
    preserve_split = true
}

master {
    new_status = master
}

# Gestures
gestures {
    workspace_swipe = true
    workspace_swipe_fingers = 3
}

# GPU-specific rendering settings
$(generate_gpu_render_settings)

# Misc settings
misc {
    disable_hyprland_logo = true
    disable_splash_rendering = true
    mouse_move_enables_dpms = true
    key_press_enables_dpms = true
}

# Window rules
windowrulev2 = suppressevent maximize, class:.*
windowrulev2 = float, class:^(pavucontrol)$
windowrulev2 = float, class:^(blueman-manager)$
windowrulev2 = float, class:^(nm-connection-editor)$

# Keybindings
\$mainMod = SUPER

# Application shortcuts
bind = \$mainMod, RETURN, exec, kitty
bind = \$mainMod, Q, killactive,
bind = \$mainMod, M, exit,
bind = \$mainMod, E, exec, thunar
bind = \$mainMod, V, togglefloating,
bind = \$mainMod, R, exec, $LAUNCHER_CMD
bind = \$mainMod, P, pseudo,
bind = \$mainMod, J, togglesplit,
bind = \$mainMod, F, fullscreen,
bind = \$mainMod SHIFT, C, exec, cliphist list | rofi -dmenu | cliphist decode | wl-copy

# Move focus with arrow keys
bind = \$mainM
