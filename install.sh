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
    "base-devel"
)

# Get passwords securely at the beginning
echo "Please set your passwords:"
read -s -p "Enter root password: " ROOT_PASSWORD
echo
read -s -p "Confirm root password: " ROOT_PASSWORD_CONFIRM
echo
if [ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]; then
    echo "Root passwords do not match!"
    exit 1
fi

read -s -p "Enter user password: " USER_PASSWORD
echo
read -s -p "Confirm user password: " USER_PASSWORD_CONFIRM
echo
if [ "$USER_PASSWORD" != "$USER_PASSWORD_CONFIRM" ]; then
    echo "User passwords do not match!"
    exit 1
fi

# Update the system clock
timedatectl set-ntp true

# Partition the disk
read -p "Enter disk (e.g., /dev/sda or /dev/nvme0n1): " DISK

# Rest of your disk setup remains the same...
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

# Modified chroot commands to use the collected passwords
arch-chroot $INSTALL_DIR bash -c "
# Set timezone
ln -sf /usr/share/zoneinfo/US/Eastern /etc/localtime
hwclock --systohc

# Localization
echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf

# Network configuration
echo 'archlinux' > /etc/hostname
echo '127.0.0.1 localhost' >> /etc/hosts
echo '::1       localhost' >> /etc/hosts
echo '127.0.1.1 archlinux.localdomain archlinux' >> /etc/hosts

# Initramfs
mkinitcpio -P

# Set root password non-interactively
echo 'root:${ROOT_PASSWORD}' | chpasswd

# Bootloader installation
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Create user and set password non-interactively
useradd -m -G wheel $USER_NAME
echo '${USER_NAME}:${USER_PASSWORD}' | chpasswd

# Configure sudo
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Enable services
systemctl enable NetworkManager

# Install yay
su - $USER_NAME -c 'git clone https://aur.archlinux.org/yay.git /home/$USER_NAME/yay'
su - $USER_NAME -c 'cd /home/$USER_NAME/yay && makepkg -si --noconfirm'
"

# Clone setup repository
git clone $REPO_URL $INSTALL_DIR/home/$USER_NAME/setup
chown -R $USER_NAME:$USER_NAME $INSTALL_DIR/home/$USER_NAME/setup

echo "Base installation is complete. Reboot into your new system."
