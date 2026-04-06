#!/bin/bash

set -euo pipefail

# =============================================================================
# Arch Linux Post-Installation Script
# =============================================================================
# Installs and configures:
#   - GNOME desktop environment
#   - French locale configuration
#   - Developer tools (VSCode, Git, etc.)
#   - Common graphical apps (Chrome, PDF reader, LibreOffice, etc.)
#   - Extra utilities and fonts
# =============================================================================

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---------------------------------------------------------------------------
# Abort helper
# ---------------------------------------------------------------------------
abort() {
  error "$*"
  exit 1
}

# ---------------------------------------------------------------------------
# gsettings helper (must be defined early — used in multiple sections)
# ---------------------------------------------------------------------------
run_gsettings() {
  su - "$USERNAME" -c "gsettings set $*" 2>/dev/null || warn "Could not set: gsettings set $*"
}

# ---------------------------------------------------------------------------
# Require root
# ---------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  abort "This script must be run as root."
fi

# =============================================================================
# 1. Detect user
# =============================================================================
echo ""
info "Post-installation configuration"
echo ""

# Auto-detect the invoking user (works under sudo)
if [[ -n "${SUDO_USER:-}" ]]; then
  USERNAME="$SUDO_USER"
else
  USERNAME=$(awk -F: '$3 >= 1000 && $3 < 60000 { print $1; exit }' /etc/passwd)
fi

if [[ -z "$USERNAME" ]]; then
  read -p "No user detected. Enter username: " USERNAME
fi

if ! id "$USERNAME" &>/dev/null; then
  abort "User '$USERNAME' does not exist."
fi

info "Configuring for user: $USERNAME"
USER_HOME=$(eval echo "~$USERNAME")

# =============================================================================
# 2. Enable multilib and Chaotic-AUR (optional)
# =============================================================================
info "Enabling multilib repository..."
sed -i '/^\[multilib\]/,/Include/ s/^#//' /etc/pacman.conf

info "Synchronizing package databases..."
pacman -Sy --noconfirm

# =============================================================================
# 3. Install yay (AUR helper)
# =============================================================================
info "Installing yay (AUR helper)..."
pacman -S --needed --noconfirm base-devel git
rm -rf /tmp/yay
git clone https://aur.archlinux.org/yay.git /tmp/yay
chown -R "$USERNAME:" /tmp/yay
su - "$USERNAME" -c "cd /tmp/yay && makepkg -si --noconfirm"
rm -rf /tmp/yay
success "yay installed."

# =============================================================================
# 4. French locale configuration
# =============================================================================
info "Configuring French locales..."

# Ensure French locale is generated
sed -i 's/^#fr_FR.UTF-8 UTF-8/fr_FR.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^#fr_FR ISO-8859-1/fr_FR ISO-8859-1/' /etc/locale.gen
sed -i 's/^#fr_FR.UTF-8@euro ISO-8859-15/fr_FR.UTF-8@euro ISO-8859-15/' /etc/locale.gen 2>/dev/null || true
locale-gen

# Set system-wide locale to French
cat > /etc/locale.conf <<'EOF'
LANG=fr_FR.UTF-8
LC_TIME=fr_FR.UTF-8
LC_MONETARY=fr_FR.UTF-8
LC_NUMERIC=fr_FR.UTF-8
LC_PAPER=fr_FR.UTF-8
LC_MEASUREMENT=fr_FR.UTF-8
EOF

# Set French keyboard for console
cat > /etc/vconsole.conf <<'EOF'
KEYMAP=fr
FONT=lat9w-16
EOF

# Set French locale for the user
mkdir -p "$USER_HOME/.config"
cat > "$USER_HOME/.config/locale.conf" <<'EOF'
LANG=fr_FR.UTF-8
LC_TIME=fr_FR.UTF-8
LC_MONETARY=fr_FR.UTF-8
LC_NUMERIC=fr_FR.UTF-8
LC_PAPER=fr_FR.UTF-8
LC_MEASUREMENT=fr_FR.UTF-8
EOF
chown -R "$USERNAME:" "$USER_HOME/.config"

success "French locales configured."

# =============================================================================
# 5. Install fonts
# =============================================================================
info "Installing fonts..."
pacman -S --needed --noconfirm \
  ttf-dejavu \
  ttf-liberation \
  noto-fonts \
  noto-fonts-emoji \
  noto-fonts-cjk \
  noto-fonts-extra \
  gnu-free-fonts \
  ttf-roboto \
  ttf-jetbrains-mono \
  ttf-jetbrains-mono-nerd \
  || abort "Failed to install fonts."

success "Fonts installed."

# =============================================================================
# 6. Install GNOME desktop environment
# =============================================================================
info "Installing GNOME desktop environment..."
pacman -S --needed --noconfirm \
  gnome \
  gnome-tweaks \
  gnome-shell-extensions \
  gnome-browser-connector \
  || abort "Failed to install GNOME."

# Enable GDM (GNOME Display Manager)
info "Enabling GDM..."
systemctl enable gdm

# Enable NetworkManager
systemctl enable NetworkManager

# Enable Bluetooth (if available)
if pacman -Qq bluez &>/dev/null; then
  systemctl enable bluetooth
fi

# Enable printing
if pacman -Qq cups &>/dev/null; then
  systemctl enable cups
fi

success "GNOME installed and services enabled."

# =============================================================================
# 6b. Power management for GNOME
# =============================================================================
info "Configuring power management..."

pacman -S --needed --noconfirm \
  upower \
  power-profiles-daemon \
  acpi \
  || abort "Failed to install power management packages."

systemctl enable --now upower
systemctl enable --now power-profiles-daemon

success "Power management configured."

# =============================================================================
# 7. Install developer tools
# =============================================================================
info "Installing developer tools..."
pacman -S --needed --noconfirm \
  git \
  neovim \
  tmux \
  ripgrep \
  fzf \
  bat \
  eza \
  zoxide \
  starship \
  docker \
  docker-compose \
  lazygit \
  meld \
  || abort "Failed to install developer tools."

# Enable and start Docker
info "Enabling and starting Docker..."
systemctl enable --now docker
usermod -aG docker "$USERNAME"

success "Developer tools installed."

# =============================================================================
# 8. Install VSCode (via AUR)
# =============================================================================
info "Installing Visual Studio Code..."
su - "$USERNAME" -c "yay -S --needed --noconfirm visual-studio-code-bin"
success "VSCode installed."

# =============================================================================
# 8b. Install and configure OpenCode (AI coding assistant)
# =============================================================================
info "Installing OpenCode (AI coding assistant)..."
su - "$USERNAME" -c "yay -S --needed --noconfirm opencode"
success "OpenCode installed."

# Configure OpenCode with qwen3.6-plus-free via Zen (free, no API key needed)
info "Configuring OpenCode with Zen (qwen3.6-plus-free)..."

OPENCODE_CONFIG_DIR="$USER_HOME/.config/opencode"
mkdir -p "$OPENCODE_CONFIG_DIR"

cat > "$OPENCODE_CONFIG_DIR/opencode.json" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "model": {
    "default": "zen/qwen/qwen3.6-plus-free"
  }
}
EOF

chown -R "$USERNAME:" "$OPENCODE_CONFIG_DIR"

success "OpenCode configured with qwen3.6-plus-free via Zen (free, no API key needed)."

# =============================================================================
# 8c. Install VSCode extensions for web development
# =============================================================================
info "Installing VSCode extensions for web development..."

VSCODE_EXTENSIONS=(
  # Web development
  "ms-vscode.vscode-typescript-next"
  "dbaeumer.vscode-eslint"
  "esbenp.prettier-vscode"
  "ms-vscode.live-server"
  "ritwickdey.LiveServer"
  "formulahendry.auto-rename-tag"
  "formulahendry.auto-close-tag"
  "christian-kohler.path-intellisense"
  "christian-kohler.npm-intellisense"
  "ms-vscode.vscode-json"
  "bradlc.vscode-tailwindcss"
  "styled-components.vscode-styled-components"
  "dsznajder.es7-react-js-snippets"

  # Languages & frameworks
  "Vue.volar"
  "svelte.svelte-vscode"
  "ms-python.python"
  "ms-python.vscode-pylance"
  "ms-toolsai.jupyter"
  "rust-lang.rust-analyzer"
  "golang.go"

  # Docker & DevOps
  "ms-azuretools.vscode-docker"
  "ms-vscode-remote.remote-containers"
  "ms-vscode-remote.remote-ssh"
  "ms-vscode-remote.remote-ssh-edit"

  # Git & productivity
  "eamodio.gitlens"
  "github.vscode-github-actions"
  "github.copilot"
  "github.copilot-chat"

  # UI & themes
  "pkief.material-icon-theme"
  "equinusocio.vsc-material-theme"
  "streetsidesoftware.code-spell-checker"

  # Utilities
  "gruntfuggly.todo-tree"
  "oderwat.indent-rainbow"
  "mosapride.zenkaku"
  "mechatroner.rainbow-csv"
)

for ext in "${VSCODE_EXTENSIONS[@]}"; do
  su - "$USERNAME" -c "code --install-extension ${ext} --force" 2>/dev/null || \
    warn "Could not install extension: $ext"
done

success "VSCode extensions installed."

# =============================================================================
# 9. Install Google Chrome (via AUR)
# =============================================================================
info "Installing Google Chrome..."
su - "$USERNAME" -c "yay -S --needed --noconfirm google-chrome"
success "Google Chrome installed."

# =============================================================================
# 9b. Install additional browsers for web development
# =============================================================================
info "Installing additional browsers for web development..."

# Firefox (official)
pacman -S --needed --noconfirm \
  firefox \
  firefox-i18n-fr \
  || warn "Could not install Firefox, skipping."

# Brave (via AUR)
su - "$USERNAME" -c "yay -S --needed --noconfirm brave-bin" 2>/dev/null || \
  warn "Could not install Brave, skipping."

# Set Firefox as default browser
run_gsettings "org.gnome.shell favorite-apps \"['firefox.desktop', 'code.desktop', 'org.gnome.Nautilus.desktop', 'google-chrome.desktop']\"" 2>/dev/null || true

success "Additional browsers installed."

# =============================================================================
# 10. Install common graphical applications
# =============================================================================
info "Installing common graphical applications..."

# PDF reader
pacman -S --needed --noconfirm \
  evince \
  || abort "Failed to install PDF reader."

# LibreOffice
pacman -S --needed --noconfirm \
  libreoffice-fresh \
  libreoffice-fresh-fr \
  || abort "Failed to install LibreOffice."

# Image viewer
pacman -S --needed --noconfirm \
  loupe \
  || warn "Could not install Loupe, skipping."

# Archive manager
pacman -S --needed --noconfirm \
  file-roller \
  || warn "Could not install File Roller, skipping."

# Text editor (GNOME)
pacman -S --needed --noconfirm \
  gedit \
  || warn "Could not install Gedit, skipping."

# Terminal (GNOME Console / Kitty as alternative)
pacman -S --needed --noconfirm \
  gnome-console \
  kitty \
  || warn "Could not install terminal emulators, skipping."

# Media player
pacman -S --needed --noconfirm \
  vlc \
  || warn "Could not install VLC, skipping."

# Screenshot tool
pacman -S --needed --noconfirm \
  gnome-screenshot \
  flameshot \
  || warn "Could not install screenshot tools, skipping."

# Disk usage analyzer
pacman -S --needed --noconfirm \
  baobab \
  || warn "Could not install Baobab, skipping."

# System monitor
pacman -S --needed --noconfirm \
  gnome-system-monitor \
  || warn "Could not install GNOME System Monitor, skipping."

# Communication
pacman -S --needed --noconfirm \
  thunderbird \
  thunderbird-i18n-fr \
  || warn "Could not install Thunderbird, skipping."

success "Common graphical applications installed."

# =============================================================================
# 11. Install extra utilities
# =============================================================================
info "Installing extra utilities..."
pacman -S --needed --noconfirm \
  wget \
  curl \
  unzip \
  p7zip \
  rsync \
  htop \
  btop \
  ncdu \
  tree \
  jq \
  python \
  python-pip \
  nodejs \
  npm \
  || abort "Failed to install extra utilities."

success "Extra utilities installed."

# =============================================================================
# 12. Install GNOME extensions (popular ones)
# =============================================================================
info "Installing popular GNOME Shell extensions..."
pacman -S --needed --noconfirm \
  gnome-shell-extension-appindicator \
  gnome-shell-extension-dash-to-dock \
  gnome-shell-extension-dash-to-panel \
  gnome-shell-extension-caffeine \
  gnome-shell-extension-clipboard-indicator \
  gnome-shell-extension-burn-my-windows \
  || warn "Some GNOME extensions could not be installed."

success "GNOME extensions installed."

# =============================================================================
# 13. Configure GNOME defaults for French user
# =============================================================================
info "Configuring GNOME defaults..."

# Input sources — French + English (for QWERTY keyboards with French locales)
run_gsettings "org.gnome.desktop.input-sources sources \"[('xkb', 'fr'), ('xkb', 'us')]\""

# Clock format — 24h
run_gsettings "org.gnome.desktop.interface clock-format '24h'"

# Date format
run_gsettings "org.gnome.desktop.interface show-date true"
run_gsettings "org.gnome.desktop.interface show-weekday true"

# Natural scrolling
run_gsettings "org.gnome.desktop.peripherals.touchpad natural-scroll true"

# Tap to click
run_gsettings "org.gnome.desktop.peripherals.touchpad tap-to-click true"

# Disable hot corner
run_gsettings "org.gnome.desktop.interface enable-hot-corners false"

# Dark mode preference (optional — set to default light)
run_gsettings "org.gnome.desktop.interface color-scheme 'default'"

# Default applications
run_gsettings "org.gnome.desktop.default-applications.office.calendar exec 'org.gnome.Calendar'"
run_gsettings "org.gnome.desktop.default-applications.office.tasks exec 'org.gnome.Tasks'"

success "GNOME defaults configured."

# =============================================================================
# 15. Configure shell for the user (optional nice defaults)
# =============================================================================
info "Configuring user shell defaults..."

# Set VSCode as the default editor system-wide (idempotent)
if ! grep -q 'export EDITOR="code --wait"' "$USER_HOME/.bashrc" 2>/dev/null; then
  echo 'export EDITOR="code --wait"' >> "$USER_HOME/.bashrc"
  echo 'export VISUAL="code --wait"' >> "$USER_HOME/.bashrc"
fi

# Add useful aliases to user's .bashrc (idempotent)
if ! grep -q '# --- Custom aliases ---' "$USER_HOME/.bashrc" 2>/dev/null; then
  cat >> "$USER_HOME/.bashrc" <<'EOF'

# --- Custom aliases ---
alias ll='eza -la --icons=auto'
alias lt='eza --tree --icons=auto'
alias cat='bat --paging=never'
alias grep='rg'
alias find='fd'
alias cd='z'
alias htop='btop'
alias vim='code'
alias vi='code'
alias nano='code'
alias code='code --no-sandbox'
EOF
fi

chown "$USERNAME:" "$USER_HOME/.bashrc"

# Set default shell to bash if not already
chsh -s /bin/bash "$USERNAME" 2>/dev/null || true

chown "$USERNAME:" "$USER_HOME/.bashrc"

success "User shell configured."

# =============================================================================
# 15. Clean up
# =============================================================================
info "Cleaning up package cache..."
pacman -Scc --noconfirm

success "Cleanup complete."

# =============================================================================
# 16. Summary
# =============================================================================
echo ""
success "============================================"
success "  Post-installation complete!"
success "============================================"
echo ""
info "Installed:"
info "  - GNOME desktop environment"
info "  - French locale configuration"
info "  - Developer tools (Git, Neovim, etc.)"
info "  - OpenCode (AI coding assistant) with qwen3.6-plus-free"
info "  - VSCode + 30+ web dev extensions"
info "  - Firefox, Google Chrome, Brave"
info "  - Docker + Docker Compose (enabled & started)"
info "  - LibreOffice (French), Evince (PDF)"
info "  - VLC, Thunderbird (French), Flameshot"
info "  - GNOME extensions and tweaks"
info "  - Extra utilities (btop, fd, rg, bat, etc.)"
echo ""
info "Reboot to start GNOME:  reboot"
echo ""
