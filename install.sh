#!/bin/bash

# WARNING: This script will destroy all data on the selected disk.
# Run it at your own risk. It is highly recommended to test this script
# in a virtual machine before running it on a physical machine.

set -euo pipefail

# --- Configuration ---

# Ask for the disk to use
lsblk -d -o NAME,SIZE,MODEL
read -p "Enter the disk to install Arch Linux on (e.g., /dev/sda): " DISK

# Verify that the selected disk exists
if [ ! -b "$DISK" ]; then
    echo "Error: Disk $DISK not found."
    exit 1
fi

# Ask for the size of the swap partition
read -p "Enter the size of the swap partition in gigabytes (e.g., 8 for 8G): " SWAP_SIZE

# Ask for the LUKS passphrase
read -s -p "Enter the passphrase for the encrypted partition: " LUKS_PASSWORD
echo
read -s -p "Confirm the passphrase: " LUKS_PASSWORD_CONFIRM
echo

if [ "$LUKS_PASSWORD" != "$LUKS_PASSWORD_CONFIRM" ]; then
    echo "Error: Passphrases do not match."
    exit 1
fi

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

echo "--- Formatting partitions ---"

# --- LUKS Encryption ---
echo "--- Setting up LUKS encryption on $LUKS_PARTITION ---"
echo -n "$LUKS_PASSWORD" | cryptsetup luksFormat "$LUKS_PARTITION" -
echo -n "$LUKS_PASSWORD" | cryptsetup open "$LUKS_PARTITION" cryptroot -

# --- Formatting ---
echo "--- Formatting partitions ---"
mkfs.fat -F32 "$EFI_PARTITION"
mkswap "$SWAP_PARTITION"
mkfs.ext4 /dev/mapper/cryptroot

# --- Mounting ---
echo "--- Mounting partitions ---"
mount /dev/mapper/cryptroot /mnt
mkdir -p /mnt/boot
mount "$EFI_PARTITION" /mnt/boot
swapon "$SWAP_PARTITION"

echo "--- Base installation ---"
echo "The script has completed the partitioning, encryption, and mounting steps."
echo "You can now proceed with the base installation using pacstrap:"
echo
echo "pacstrap /mnt base linux linux-firmware"
echo
echo "After that, you will need to chroot into the new system and complete the installation."

exit 0
