#!/bin/bash

set -euo pipefail  # Exit on error, unset variables, and pipe failures

# Define readonly variables
readonly CODENAME=sid
readonly TARGET_DIR=./dist
readonly MIRROR=https://deb.debian.org/debian-ports
readonly KEYRING=/usr/share/keyrings/debian-ports-archive-keyring.gpg
readonly ROOT_FS=./rootfs.tar.xz
readonly BOOT_FS=./bootfs.tar.xz
readonly PATCH_DIR=kernel_patches
readonly KERNEL_VER=6.6.67
readonly CONFIG_FILE=config-$KERNEL_VER-PS3
readonly LOCAL_VER="-amdexa"
readonly HOSTNAME="ps3Linux64"

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

#copying kernel patches
echo "copying kernel patches and config.."
cp -r $PATCH_DIR $TARGET_DIR/tmp/
cp -r $CONFIG_FILE $TARGET_DIR/tmp/

# Chroot into the target directory and configure the system
sudo chroot "$TARGET_DIR" /bin/bash <<EOF

# Update sources and install necessary packages
apt modernize-sources -y
apt update
DEBIAN_FRONTEND=noninteractive apt install -y debian-ports-archive-keyring
apt update
DEBIAN_FRONTEND=noninteractive apt install -y wget curl python3 dialog file git kmod openssh-server sudo vim iputils-ping net-tools network-manager \
 build-essential flex bison libncurses-dev libssl-dev bc dwarves cpio rsync libelf-dev libdebuginfod-dev dracut

# Enable NetworkManager on boot
systemctl enable NetworkManager

# fetching and building the kernel
wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KERNEL_VER.tar.xz -P /usr/src/
cd /usr/src
tar -xf linux-$KERNEL_VER.tar.xz
rm linux-$KERNEL_VER.tar.xz
cd linux-$KERNEL_VER
cp /tmp/$CONFIG_FILE .config
for patch in "/tmp/$PATCH_DIR"/*.patch ; do [ -f "\$patch" ] && patch -p1 < "\$patch"; done

KBUILD_BUILD_HOST="\$(hostname --fqdn)"

make -j\$(nproc) olddefconfig
make -j\$(nproc)
make -j\$(nproc) install
make -j\$(nproc) modules_install
make -j\$(nproc) headers_install

cd ~
# remove the Linux source directory to reduce the image size, although I wish I could keep it.
rm -rf /usr/src/linux-$KERNEL_VER

dracut --xz -o 'qemu' -o 'qemu-net' --force --kernel-image '/boot/vmlinux-$KERNEL_VER$LOCAL_VER' --kver '$KERNEL_VER$LOCAL_VER'

# configs
echo "$HOSTNAME" > /etc/hostname
grep spufs /etc/fstab > /dev/null || echo "spufs /spu spufs rw,relatime,mode=40755 0 0" >> /etc/fstab

mkdir /spu

# Clean up
apt clean
EOF

# Unmount filesystems
echo "unmounting temp filesystems.."
sudo umount "$TARGET_DIR/dev"
sudo umount "$TARGET_DIR/proc"
sudo umount "$TARGET_DIR/sys"

# Create a compressed tar archive of boot fs
echo "creating a tar archive of the boot filesystem.."
sudo tar -cJf "$BOOT_FS" -C "$TARGET_DIR/boot" .

# cleanup kernel and initrd images
sudo rm -f "$TARGET_DIR/boot/vmlinux-$KERNEL_VER$LOCAL_VER"
sudo rm -f "$TARGET_DIR/boot/initrd.img-$KERNEL_VER$LOCAL_VER"

# Create a compressed tar archive of root fs
echo "creating a tar archive of the root filesystem.."
sudo tar --numeric-owner -cJf "$ROOT_FS" -C "$TARGET_DIR" .

echo "Debian PPC64 $CODENAME archives are ready: root FS:$ROOT_FS, boot FS: $BOOT_FS."

