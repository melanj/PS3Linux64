#!/bin/bash

set -euo pipefail  # Exit on error, unset variables, and pipe failures

# Define readonly variables
readonly CODENAME=sid
readonly TARGET_DIR=./dist
readonly MIRROR=https://deb.debian.org/debian-ports
readonly KEYRING=/usr/share/keyrings/debian-ports-archive-keyring.gpg
readonly TAR_IMAGE=./rootfs.tar.xz

# Ensure target directory exists
mkdir -p "$TARGET_DIR"

# Run debootstrap
echo "Running debootstrap to create a Debian $CODENAME root filesystem at $TARGET_DIR..."
sudo debootstrap --arch=ppc64 --variant=buildd --keyring="$KEYRING" "$CODENAME" "$TARGET_DIR" "$MIRROR"

# Mount necessary filesystems
echo "mounting necessary filesystems.."
sudo mount --bind /dev "$TARGET_DIR/dev"
sudo mount --bind /proc "$TARGET_DIR/proc"
sudo mount --bind /sys "$TARGET_DIR/sys"

# Chroot into the target directory and configure the system
sudo chroot "$TARGET_DIR" /bin/bash <<EOF

# Update sources and install necessary packages
apt modernize-sources -y
apt update
apt install -y debian-ports-archive-keyring
apt update
apt install -y wget curl python3 dialog file git kmod openssh-server sudo vim iputils-ping net-tools network-manager

# Enable NetworkManager on boot
systemctl enable NetworkManager

# Clean up
apt clean
EOF

# Unmount filesystems
echo "unmounting temp filesystems.."
sudo umount "$TARGET_DIR/dev"
sudo umount "$TARGET_DIR/proc"
sudo umount "$TARGET_DIR/sys"

# Create a compressed tar archive
echo "creating a tar archive of the root filesystem.."
sudo tar --numeric-owner -cJf "$TAR_IMAGE" -C "$TARGET_DIR" .

echo "Debian $CODENAME root filesystem archive is ready at $TAR_IMAGE."

