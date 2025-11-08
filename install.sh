#!/bin/bash

# WARNING: This script will destroy all data on the selected disk.
# Run it at your own risk. It is highly recommended to test this script
# in a virtual machine before running it on a physical machine.

set -euo pipefail

# --- Preliminary cleanup ---
# Try to unmount and close devices that might be left over from a previous run.
echo "--- Cleaning up from any previous failed runs ---"
umount -R /mnt &>/dev/null || true
cryptsetup close cryptroot &>/dev/null || true
echo "--- Cleanup complete ---"

# --- Configuration ---

# Ask for the disk to use
lsblk -d -o NAME,SIZE,MODEL
while true; do
    read -p "Enter the disk to install Arch Linux on (e.g., /dev/sda): " DISK
    if [ -b "$DISK" ]; then
        read -p "Are you sure you want to use $DISK? This will destroy all data on it. (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            break
        fi
    else
        echo "Error: Disk $DISK not found. Please enter a valid disk."
    fi
done

# Ask for the size of the swap partition
while true; do
    read -p "Enter the size of the swap partition in gigabytes (e.g., 8 for 8G): " SWAP_SIZE
    if [[ "$SWAP_SIZE" =~ ^[0-9]+$ ]] && [ "$SWAP_SIZE" -gt 0 ]; then
        break
    else
        echo "Error: Please enter a positive number for the swap size."
    fi
done

# Ask for the LUKS passphrase
while true; do
    read -s -p "Enter the passphrase for the encrypted partition: " LUKS_PASSWORD
    echo
    read -s -p "Confirm the passphrase: " LUKS_PASSWORD_CONFIRM
    echo

    if [ -z "$LUKS_PASSWORD" ]; then
        echo "Error: Passphrase cannot be empty."
    elif [ "$LUKS_PASSWORD" != "$LUKS_PASSWORD_CONFIRM" ]; then
        echo "Error: Passphrases do not match."
    else
        break
    fi
done

# Ask for username
while true; do
    read -p "Enter the username for the new user: " USERNAME
    if [ -n "$USERNAME" ]; then
        break
    else
        echo "Error: Username cannot be empty."
    fi
done

# Ask for user password
while true; do
    read -s -p "Enter the password for the new user: " USER_PASSWORD
    echo
    read -s -p "Confirm the password: " USER_PASSWORD_CONFIRM
    echo

    if [ -z "$USER_PASSWORD" ]; then
        echo "Error: Password cannot be empty."
    elif [ "$USER_PASSWORD" != "$USER_PASSWORD_CONFIRM" ]; then
        echo "Error: Passwords do not match."
    else
        break
    fi
done

# Ask for root password
while true; do
    read -s -p "Enter the password for the root user: " ROOT_PASSWORD
    echo
    read -s -p "Confirm the password: " ROOT_PASSWORD_CONFIRM
    echo

    if [ -z "$ROOT_PASSWORD" ]; then
        echo "Error: Password cannot be empty."
    elif [ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]; then
        echo "Error: Passwords do not match."
    else
        break
    fi
done

# Ask for hostname
while true; do
    read -p "Enter the hostname for the new system: " HOSTNAME
    if [ -n "$HOSTNAME" ]; then
        break
    else
        echo "Error: Hostname cannot be empty."
    fi
done

# --- Partitioning ---

echo "--- Partitioning $DISK ---"

# Wipe the partition table
sgdisk --zap-all "$DISK"

# Create partitions
# 1: EFI System Partition (512M)
# 2: Linux swap
# 3: Linux filesystem (LUKS)
sgdisk --new=1:0:+512M --typecode=1:ef00 "$DISK"
sgdisk --new=2:0:+${SWAP_SIZE}G --typecode=2:8200 "$DISK"
sgdisk --new=3:0:0 --typecode=3:8300 "$DISK"

# Inform the kernel about the partition table changes
partprobe "$DISK"

# Wait for the partitions to be created
sleep 2

# Get partition names
EFI_PARTITION="${DISK}1"
SWAP_PARTITION="${DISK}2"
LUKS_PARTITION="${DISK}3"

# In some systems, partition names might be different (e.g., /dev/nvme0n1p1)
if [ ! -e "$EFI_PARTITION" ]; then
    EFI_PARTITION="${DISK}p1"
    SWAP_PARTITION="${DISK}p2"
    LUKS_PARTITION="${DISK}p3"
fi

echo "--- Formatting partitions and setting up encryption ---"

# --- LUKS Encryption ---
echo "--- Setting up LUKS encryption on $LUKS_PARTITION ---"
echo -n "$LUKS_PASSWORD" | cryptsetup luksFormat "$LUKS_PARTITION" -
echo -n "$LUKS_PASSWORD" | cryptsetup open "$LUKS_PARTITION" cryptroot -

# --- Formatting ---
mkfs.fat -F32 "$EFI_PARTITION"
swapoff "$SWAP_PARTITION" &>/dev/null || true
mkswap "$SWAP_PARTITION"
mkfs.ext4 /dev/mapper/cryptroot

# --- Mounting ---
echo "--- Mounting partitions ---"
mount /dev/mapper/cryptroot /mnt
mkdir -p /mnt/boot
mount "$EFI_PARTITION" /mnt/boot
swapon "$SWAP_PARTITION"

echo "--- Base installation ---"
pacstrap /mnt base linux linux-firmware

# --- Generate fstab ---
genfstab -U /mnt >> /mnt/etc/fstab

LUKS_UUID=$(blkid -s UUID -o value "$LUKS_PARTITION")

# --- Detect CPU vendor for microcode ---
if grep -q "GenuineIntel" /proc/cpuinfo; then
    UCODE_PACKAGE="intel-ucode"
elif grep -q "AuthenticAMD" /proc/cpuinfo; then
    UCODE_PACKAGE="amd-ucode"
else
    UCODE_PACKAGE=""
fi

# --- Chroot commands ---
arch-chroot /mnt bash -c "ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime"
arch-chroot /mnt bash -c "hwclock --systohc"
arch-chroot /mnt bash -c "echo \"KEYMAP=fr\" > /etc/vconsole.conf"
arch-chroot /mnt bash -c "sed -i 's/^#fr_FR.UTF-8 UTF-8/fr_FR.UTF-8 UTF-8/' /etc/locale.gen"
arch-chroot /mnt bash -c "locale-gen"
arch-chroot /mnt bash -c "echo \"LANG=fr_FR.UTF-8\" > /etc/locale.conf"
arch-chroot /mnt bash -c "echo \"$HOSTNAME\" > /etc/hostname"
arch-chroot /mnt bash -c "pacman -S --noconfirm grub efibootmgr sudo $UCODE_PACKAGE"
arch-chroot /mnt bash -c "sed -i \"s/GRUB_CMDLINE_LINUX_DEFAULT=\\\"loglevel=3 quiet\\\"/GRUB_CMDLINE_LINUX_DEFAULT=\\\"loglevel=3 quiet cryptdevice=UUID=${LUKS_UUID}:cryptroot root=\\\/dev\\\/mapper\\\/cryptroot\\\"/\" /etc/default/grub"
arch-chroot /mnt bash -c "grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB"
arch-chroot /mnt bash -c "grub-mkconfig -o /boot/grub/grub.cfg"
arch-chroot /mnt bash -c "useradd -m -g users -G wheel -s /bin/bash \"$USERNAME\""
arch-chroot /mnt bash -c "echo \"$USERNAME:$USER_PASSWORD\" | chpasswd"
arch-chroot /mnt bash -c "sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers"
arch-chroot /mnt bash -c "echo \"root:$ROOT_PASSWORD\" | chpasswd"

# --- Unmount ---
umount -R /mnt
swapoff "$SWAP_PARTITION"
cryptsetup close cryptroot

echo "--- Installation complete ---"
echo "You can now reboot your system."

exit 0
