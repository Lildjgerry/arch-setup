#!/bin/bash

# Exit on errors
set -e

# Define variables
REPO_URL="https://github.com/lildjgerry/arch-setup.git"
INSTALL_DIR="/mnt"
USER_NAME="gerry"
PACKAGES=(
    "base"
    "linux"
    "linux-firmware"
    "hyprland"
    "firefox"
    "nano"
    "sudo"
    "waybar"
    "networkmanager"
    "git"
    "base-devel" # Added to ensure necessary tools for AUR packages
)

# Update the system clock
timedatectl set-ntp true

# Partition the disk
read -p "Enter disk (e.g., /dev/sda or /dev/nvme0n1): " DISK

# Detect if the disk is NVMe and set partition names accordingly
if [[ $DISK == *"nvme"* ]]; then
    PART1="${DISK}p1"
    PART2="${DISK}p2"
else
    PART1="${DISK}1"
    PART2="${DISK}2"
fi

parted $DISK mklabel gpt
parted $DISK mkpart primary fat32 1MiB 512MiB
parted $DISK set 1 boot on
parted $DISK mkpart primary ext4 512MiB 100%

# Format the partitions
mkfs.fat -F32 $PART1
mkfs.ext4 $PART2

# Mount the partitions
mount $PART2 $INSTALL_DIR
mkdir -p $INSTALL_DIR/boot
mount $PART1 $INSTALL_DIR/boot

# Install the base system
pacstrap $INSTALL_DIR ${PACKAGES[@]}

# Generate fstab
genfstab -U $INSTALL_DIR >> $INSTALL_DIR/etc/fstab

# Chroot into the new system
arch-chroot $INSTALL_DIR <<EOF

# Set timezone
ln -sf /usr/share/zoneinfo/US/Eastern /etc/localtime
hwclock --systohc

# Localization
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Network configuration
echo "archlinux" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1       localhost" >> /etc/hosts
echo "127.0.1.1 archlinux.localdomain archlinux" >> /etc/hosts

# Initramfs
mkinitcpio -P

# Set root password
passwd

# Bootloader installation
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Enable os-prober if dual-booting is needed
#sed -i 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub

# Create a user
useradd -m -G wheel $USER_NAME
while true; do
    echo "Set password for $USER_NAME:"
    if passwd $USER_NAME; then
        break
    else
        echo "Error setting password. Please try again."
    fi
done

# Configure sudo
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Enable services
systemctl enable NetworkManager

# Install yay (AUR helper)
su - $USER_NAME -c "git clone https://aur.archlinux.org/yay.git /home/$USER_NAME/yay"
su - $USER_NAME -c "cd /home/$USER_NAME/yay && makepkg -si --noconfirm"
EOF

# Clone setup repository
git clone $REPO_URL $INSTALL_DIR/home/$USER_NAME/setup
chown -R $USER_NAME:$USER_NAME $INSTALL_DIR/home/$USER_NAME/setup

# Done!
echo "Base installation is complete. Reboot into your new system."
