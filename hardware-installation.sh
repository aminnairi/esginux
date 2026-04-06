#!/bin/bash

set -euo pipefail

# =============================================================================
# Arch Linux Hardware Installation Script
# =============================================================================
# This script automates the classic Arch Linux installation process.
# Disk partitioning:
#   - SWAP: RAM × 1.5
#   - BOOT: 1 Go
#   - ROOT: remaining space (LUKS2 encrypted)
# No separate /home partition.
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
# Require root
# ---------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  abort "This script must be run as root."
fi

# ---------------------------------------------------------------------------
# Verify we are running from the Arch ISO environment
# ---------------------------------------------------------------------------
if [[ ! -f /etc/arch-release ]]; then
  abort "This script must be run from an Arch Linux live environment."
fi

# Prevent running on an already-installed system
if [[ ! -d /run/archiso/bootmnt ]]; then
  abort "This script must be run from the Arch Linux live ISO, not from an installed system."
fi

# =============================================================================
# 1. Detect available disks
# =============================================================================
info "Detecting available block devices..."

mapfile -t DISKS < <(lsblk -dnpo NAME,TYPE,SIZE | awk '$2 == "disk" { print $1 }')

if [[ ${#DISKS[@]} -eq 0 ]]; then
  abort "No disk found."
fi

echo ""
info "Available disks:"
for i in "${!DISKS[@]}"; do
  SIZE=$(lsblk -dnpo SIZE "${DISKS[$i]}")
  MODEL=$(lsblk -dnpo MODEL "${DISKS[$i]}" 2>/dev/null || echo "unknown")
  echo "  [$i] ${DISKS[$i]} — $SIZE — $MODEL"
done
echo ""

read -p "Select the target disk number [0]: " DISK_INDEX
DISK_INDEX="${DISK_INDEX:-0}"
DISK_INDEX=$(echo "$DISK_INDEX" | tr -cd '0-9')
DISK_INDEX="${DISK_INDEX:-0}"

if [[ -z "${DISKS[$DISK_INDEX]+x}" ]]; then
  abort "Invalid disk selection: index out of range."
fi

DISK="${DISKS[$DISK_INDEX]}"
info "Target disk: $DISK"

# =============================================================================
# 2. Calculate partition sizes
# =============================================================================
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_MB=$(( TOTAL_RAM_KB / 1024 ))
SWAP_SIZE_MB=$( echo "$TOTAL_RAM_MB * 1.5" | bc | awk '{printf "%d", $1}' )
SWAP_SIZE_GB=$(( (SWAP_SIZE_MB + 1023) / 1024 ))

BOOT_SIZE_MB=1024  # 1 Go

info "Total RAM: $(( TOTAL_RAM_MB / 1024 )) Go"
info "SWAP size (RAM × 1.5): ${SWAP_SIZE_MB} Mo (~${SWAP_SIZE_GB} Go)"
info "BOOT size: ${BOOT_SIZE_MB} Mo (1 Go)"
info "ROOT size: remaining space (will be LUKS2 encrypted)"

# =============================================================================
# 3. Confirm before wiping the disk
# =============================================================================
echo ""
warn "WARNING: All data on $DISK will be ERASED."
read -p "Type 'YES' to continue: " CONFIRM
if [[ "$CONFIRM" != "YES" ]]; then
  abort "Installation cancelled."
fi

# =============================================================================
# 4. Wipe existing partition table and create new GPT layout
# =============================================================================
info "Wiping existing partition table on $DISK ..."
wipefs -a "$DISK" >/dev/null 2>&1
sgdisk --zap-all "$DISK" >/dev/null 2>&1

info "Creating GPT partition table..."

# Partition 1 — EFI System Partition (BOOT)  — 1 Go
sgdisk -n 1:0:+${BOOT_SIZE_MB}M -t 1:ef00 -c 1:"EFI System" "$DISK"

# Partition 2 — SWAP — RAM × 1.5
sgdisk -n 2:0:+${SWAP_SIZE_MB}M -t 2:8200 -c 2:"Linux Swap" "$DISK"

# Partition 3 — ROOT — remaining space
sgdisk -n 3:0:0 -t 3:8304 -c 3:"Linux Root (x86-64)" "$DISK"

partprobe "$DISK" 2>/dev/null || true
sleep 2

BOOT_PART="${DISK}1"
SWAP_PART="${DISK}2"
ROOT_PART="${DISK}3"

info "Partitions created:"
lsblk -f "$DISK"

# =============================================================================
# 5. Format boot and swap partitions
# =============================================================================
info "Formatting boot and swap partitions..."

info "Formatting $BOOT_PART as FAT32 (EFI)..."
mkfs.fat -F 32 "$BOOT_PART"

info "Formatting $SWAP_PART as swap..."
mkswap "$SWAP_PART"

success "Boot and swap partitions formatted."

# =============================================================================
# 6. Encrypt root partition with LUKS2
# =============================================================================
echo ""
warn "Disk Encryption (LUKS2)"
warn "The root partition will be fully encrypted."
warn "You will need to enter this passphrase at every boot."
echo ""

read -p "Enter LUKS passphrase: " -s LUKS_PASSPHRASE
echo ""
read -p "Confirm LUKS passphrase: " -s LUKS_PASSPHRASE_CONFIRM
echo ""

if [[ "$LUKS_PASSPHRASE" != "$LUKS_PASSPHRASE_CONFIRM" ]]; then
  abort "LUKS passphrases do not match."
fi

if [[ ${#LUKS_PASSPHRASE} -lt 8 ]]; then
  abort "LUKS passphrase must be at least 8 characters."
fi

info "Encrypting $ROOT_PART with LUKS2 (this may take a moment)..."
echo -n "$LUKS_PASSPHRASE" | cryptsetup luksFormat --type luks2 --batch-mode "$ROOT_PART" -

info "Opening encrypted container as 'cryptroot'..."
echo -n "$LUKS_PASSPHRASE" | cryptsetup open --type luks2 "$ROOT_PART" cryptroot -

CRYPT_ROOT="/dev/mapper/cryptroot"

success "Root partition encrypted and opened."

# =============================================================================
# 7. Format and mount encrypted root
# =============================================================================
info "Formatting encrypted root partition as ext4..."
mkfs.ext4 -F "$CRYPT_ROOT"

info "Mounting encrypted root to /mnt..."
mount "$CRYPT_ROOT" /mnt

info "Creating and mounting boot partition to /mnt/boot..."
mkdir -p /mnt/boot
mount "$BOOT_PART" /mnt/boot

info "Enabling swap..."
swapon "$SWAP_PART"

success "Filesystems mounted."

# =============================================================================
# 8. Select mirror
# =============================================================================
info "Updating mirrorlist..."
if command -v reflector &>/dev/null; then
  reflector --country France --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist 2>/dev/null || true
fi

# =============================================================================
# 9. Install base system
# =============================================================================
info "Installing base system (this may take a while)..."
pacstrap -K /mnt \
  base \
  linux \
  linux-firmware \
  linux-headers \
  base-devel \
  grub \
  efibootmgr \
  networkmanager \
  vim \
  sudo \
  openssh \
  dhcpcd \
  os-prober \
  amd-ucode \
  intel-ucode \
  cryptsetup \
  || abort "pacstrap failed."

success "Base system installed."

# =============================================================================
# 10. Generate fstab
# =============================================================================
info "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab
success "fstab generated."

# =============================================================================
# 11. Collect user configuration (OUTSIDE the chroot)
# =============================================================================
echo ""
info "System configuration:"
echo ""

read -p "Hostname (default: archlinux): " HOSTNAME
HOSTNAME=${HOSTNAME:-archlinux}

read -p "Root password: " -s ROOT_PASSWORD
echo ""
read -p "Confirm root password: " -s ROOT_PASSWORD_CONFIRM
echo ""
if [[ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]]; then
  abort "Root passwords do not match."
fi

read -p "Username for the new user (default: user): " USERNAME
USERNAME=${USERNAME:-user}

read -p "Password for $USERNAME: " -s USER_PASSWORD
echo ""
read -p "Confirm password for $USERNAME: " -s USER_PASSWORD_CONFIRM
echo ""
if [[ "$USER_PASSWORD" != "$USER_PASSWORD_CONFIRM" ]]; then
  abort "User passwords do not match."
fi

# =============================================================================
# 12. Configure the installed system (arch-chroot -c)
# =============================================================================
info "Configuring the installed system..."

# --- Timezone ---
arch-chroot /mnt -c 'ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime'
arch-chroot /mnt -c 'hwclock --systohc'

# --- Locale ---
arch-chroot /mnt -c "sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen"
arch-chroot /mnt -c "sed -i 's/^#fr_FR.UTF-8 UTF-8/fr_FR.UTF-8 UTF-8/' /etc/locale.gen"
arch-chroot /mnt -c 'locale-gen'
arch-chroot /mnt -c 'echo "LANG=en_US.UTF-8" > /etc/locale.conf'

# --- Keyboard ---
arch-chroot /mnt -c 'echo "KEYMAP=fr" > /etc/vconsole.conf'

# --- Hostname ---
arch-chroot /mnt -c "echo '$HOSTNAME' > /etc/hostname"
arch-chroot /mnt -c "cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF"

# --- Root password ---
arch-chroot /mnt -c "echo 'root:${ROOT_PASSWORD}' | chpasswd"

# --- Create regular user with sudo access ---
arch-chroot /mnt -c "useradd -m -G wheel -s /bin/bash '${USERNAME}'"
arch-chroot /mnt -c "echo '${USERNAME}:${USER_PASSWORD}' | chpasswd"

# --- Sudo: ensure wheel group has full sudo access ---
arch-chroot /mnt -c "sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers"
arch-chroot /mnt -c "sed -i 's/^# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers" 2>/dev/null || true

# --- Initramfs: add encrypt hook for LUKS ---
arch-chroot /mnt -c "sed -i 's/^HOOKS=(.*)/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/' /etc/mkinitcpio.conf"
arch-chroot /mnt -c 'mkinitcpio -P'

# --- Bootloader (GRUB) with LUKS support ---
CRYPT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
arch-chroot /mnt -c "grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB"
arch-chroot /mnt -c "sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"cryptdevice=UUID=${CRYPT_UUID}:cryptroot:allow-discards /' /etc/default/grub"
arch-chroot /mnt -c 'grub-mkconfig -o /boot/grub/grub.cfg'

# --- Enable services ---
arch-chroot /mnt -c 'systemctl enable NetworkManager'
arch-chroot /mnt -c 'systemctl enable sshd'
arch-chroot /mnt -c 'systemctl enable dhcpcd'

success "System configured."

# =============================================================================
# 13. Unmount and reboot
# =============================================================================
info "Installation complete!"
info "Unmounting filesystems..."

swapoff "$SWAP_PART"
umount -R /mnt
cryptsetup close cryptroot

echo ""
success "============================================"
success "  Arch Linux installation is complete!"
success "============================================"
echo ""
info "Root partition is encrypted with LUKS2."
info "You will be prompted for the passphrase at every boot."
info "Rebooting now..."
echo ""

reboot
