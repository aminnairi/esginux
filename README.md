# esginux

Automated Arch Linux installation scripts.

> **Always read the script before running it.**

## Installation

> [!WARNING]
> This script will **wipe the entire selected disk** and use its **full capacity** to create the partition layout. All existing data will be permanently lost.

Boot from the [Arch Linux ISO](https://archlinux.org/download/), connect to the internet, then:

```bash
# 1. Download the script
curl -LO aminnairi.github.io/esginux/install.sh

# 2. Read it
less install.sh

# 3. Run it
bash install.sh
```

This will:

- **Partition** the selected disk (GPT):
  - EFI boot — 1 Go (FAT32)
  - Swap — RAM × 1.5
  - Root — remaining space (LUKS2 encrypted, ext4)
- **Install** the base system: kernel, firmware, GRUB, NetworkManager, OpenSSH, sudo, base-devel, microcode
- **Configure** timezone (Europe/Paris), locales (en_US + fr_FR), French keyboard
- **Create** root + unprivileged user (wheel/sudo access)
- **Reboot** automatically

## Update

After the first boot, log in and:

```bash
# 1. Download the script
curl -LO aminnairi.github.io/esginux/update.sh

# 2. Read it
less update.sh

# 3. Run it
sudo bash update.sh
```

This will install and configure:

### Desktop
- **GNOME** + Tweaks + Shell Extensions (AppIndicator, Dash to Dock, Caffeine, Clipboard Indicator, Burn My Windows)
- **GDM** display manager
- **Power management** (UPower, Power Profiles Daemon)

### Browsers
- **Firefox** (French)
- **Google Chrome**
- **Brave**

### Developer Tools
- **VSCode** with 30+ extensions (ESLint, Prettier, Tailwind, Docker, GitLens, Copilot, Volar, Svelte, Python, Rust, Go, Remote SSH, Dev Containers…)
- **OpenCode** — AI coding assistant pre-configured with `qwen3.6-plus-free` via Zen (free, no API key)
- **Neovim**, tmux, ripgrep, fzf, bat, eza, zoxide, starship, lazygit, meld

### Containers
- **Docker** + Docker Compose (enabled & started, user in docker group)

### Applications
- **LibreOffice** (French)
- **Evince** (PDF reader)
- **VLC** (media player)
- **Spotify**
- **OBS Studio**
- **Thunderbird** (French)
- **Discord**, **Microsoft Teams**, **Slack**
- **Flameshot** + GNOME Screenshot
- **Kitty** + GNOME Console
- Loupe, Gedit, Baobab, GNOME System Monitor, File Roller

### IT Student Tools
- **Wireshark**, **nmap** (networking & security)
- **DBeaver** (database client)
- **Insomnia** (API testing)
- **Obsidian** (markdown notes)
- **Calibre** (e-book management)
- **Remmina** + **FreeRDP** (remote access)
- **FileZilla** (FTP/SFTP)
- **GIMP**, **Inkscape** (graphics)

### Extras
- **Fonts**: Noto (CJK + emoji), JetBrains Mono + Nerd Font, Roboto, DejaVu, Liberation
- **Utilities**: wget, curl, unzip, p7zip, rsync, btop, ncdu, tree, jq, Python, Node.js/npm
- **French locale** system-wide (LANG, LC_TIME, LC_MONETARY, etc.)
- **GNOME defaults**: 24h clock, French + English keyboard layouts (`Super+Space` to switch), natural scrolling, tap-to-click
