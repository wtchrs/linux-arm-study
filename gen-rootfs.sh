#!/usr/bin/env bash
set -Eeuo pipefail

# -----------------------
# Define variables
# -----------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Colors
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BOLD=$(tput bold)
RESET=$(tput sgr0)

CURRENT_USER="${SUDO_USER:-$(id -un)}"

ALPINE_VERSION="3.22.2"
ALPINE_MAJMIN="3.22"
ALPINE_ARCH="armhf"
ALPINE_ROOTFS_URL="https://dl-cdn.alpinelinux.org/alpine/v$ALPINE_MAJMIN/releases/$ALPINE_ARCH/alpine-minirootfs-$ALPINE_VERSION-$ALPINE_ARCH.tar.gz"

ALPINE_ROOTFS_FILENAME=$(basename "$ALPINE_ROOTFS_URL")
ALPINE_ROOTFS_ARCHIVE="$SCRIPT_DIR/$ALPINE_ROOTFS_FILENAME"
ALPINE_ROOTFS_UNARCHIVED="$SCRIPT_DIR/rootfs"
ALPINE_ROOTFS_OUTPUT="$SCRIPT_DIR/alpine-rootfs.qcow2"

HOST_PLATFORM=$(uname -m)
ARM_EMULATOR=$(which qemu-arm-static)
#ARM_EMULATOR=/usr/bin/qemu-arm-static

NBD_DEV="/dev/nbd0"
PART_DEV="${NBD_DEV}p1"
MOUNT_POINT="/mnt/alpine_disk_temp"

# -----------------------
# Helpers
# -----------------------
print_log() {
    local COLOR=$1
    shift || true
    local MSG="$@"
    echo "$COLOR$MSG$RESET"
}

log_info() { print_log "$YELLOW" "$@"; }
log_error() { print_log "$RED" "$@"; }
log_success() { print_log "$GREEN" "$@"; }

safe_umount() {
    local target="$1"
    if mountpoint -q "$target"; then
        log_info "Unmount $target..."
        umount -l "$target" || true
    fi
}

run_chroot() {
    local cmd="$1"
    local chroot_sh="env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/sh -e -c"
    chroot "$MOUNT_POINT" $chroot_sh "$cmd"
}

# -----------------------
# Define traps
# -----------------------
cleanup() {
    log_info "Clean up..."
    safe_umount "$MOUNT_POINT/proc"
    safe_umount "$MOUNT_POINT/sys"
    safe_umount "$MOUNT_POINT/dev"
    safe_umount "$MOUNT_POINT"
    if [ -d "$MOUNT_POINT" ]; then
        rmdir "$MOUNT_POINT" || true
    fi
    if [ -b "$NBD_DEV" ]; then
        log_info "Clean up NBD device..."
        qemu-nbd -d "$NBD_DEV"
    fi
}
trap cleanup EXIT

error_handler() {
    local exit_code=$1
    local line_no=$2
    log_error "${BOLD}ERROR at line $line_no in ${BASH_SOURCE[0]} (code $exit_code)"
    exit "$exit_code"
}
trap 'error_handler $? $LINENO' ERR

# -----------------------
# Check requirements
# -----------------------
if [[ $EUID -ne 0 ]]; then
    log_error "Error: This script must be run as root (or using sudo). Aborting."
    false
fi

if [ "$HOST_PLATFORM" != "armv7l" ] && [ ! -x "$ARM_EMULATOR" ]; then
    log_error "Error: $ARM_EMULATOR is not found. Aborting."
    false
fi

# -----------------------
# main
# -----------------------
main() {
    log_info "Download Alpine Linux Mini root filesystem at $ALPINE_ROOTFS_ARCHIVE..."
    if [ ! -f "$ALPINE_ROOTFS_ARCHIVE" ]; then
        curl -LJ -o "$ALPINE_ROOTFS_ARCHIVE" "$ALPINE_ROOTFS_URL"
    else
        log_info "Archive already present, skipping download."
    fi

    log_info "Generate qcow2 image at $ALPINE_ROOTFS_OUTPUT..."
    qemu-img create -f qcow2 "$ALPINE_ROOTFS_OUTPUT" 2G
    chown "$CURRENT_USER:$CURRENT_USER" "$ALPINE_ROOTFS_OUTPUT"

    log_info "Load nbd module and mount image..."
    modprobe nbd max_part=8
    qemu-nbd -c /dev/nbd0 "$ALPINE_ROOTFS_OUTPUT"

    log_info "Generate partition on $NBD_DEV..."
    echo 'type=83, bootable' | sfdisk "$NBD_DEV" --force
    partprobe "$NBD_DEV"
    udevadm settle --timeout=5 || log_info "Warning: udev did not settle within timeout"

    if [ ! -b "$PART_DEV" ]; then
        log_error "Error: Partition device $PART_DEV not found after partprobe. Aborting."
        return 1
    fi

    log_info "Format $PART_DEV..."
    mkfs.ext4 -F "$PART_DEV"

    log_info "Mount $PART_DEV at $MOUNT_POINT..."
    mkdir -p "$MOUNT_POINT"
    mount "$PART_DEV" "$MOUNT_POINT"

    log_info "Unarchive $ALPINE_ROOTFS_ARCHIVE at $MOUNT_POINT"
    tar xzf "$ALPINE_ROOTFS_ARCHIVE" -C "$MOUNT_POINT/"

    log_info "Copy core ARM emulator to rootfs..."
    cp "$ARM_EMULATOR" "$MOUNT_POINT/usr/bin/"
    chmod 755 "$MOUNT_POINT/usr/bin/qemu-arm-static"

    if [ -f /etc/resolv.conf ]; then
        log_info "Copy /etc/resolv.conf into $MOUNT_POINT/etc/resolv.conf..."
        cp /etc/resolv.conf "$MOUNT_POINT/etc/resolv.conf"
    fi

    log_info "Mount pseudo-fs at $MOUNT_POINT..."
    mount -t proc none "$MOUNT_POINT/proc"
    mount --bind /sys "$MOUNT_POINT/sys"
    mount --make-rslave "$MOUNT_POINT/sys"
    mount --bind /dev "$MOUNT_POINT/dev"
    mount --make-rslave "$MOUNT_POINT/dev"

    log_info "Enter chroot into $MOUNT_POINT and configure the Alpine system..."

    log_info "[chroot] Install needed packages..."
    run_chroot "
        apk update;
        apk add --no-cache alpine-base openrc shadow sudo bash coreutils util-linux;"

    log_info "[chroot] Configure agetty and openrc services..."
    run_chroot "
        echo 'ttyAMA0::respawn:/sbin/getty -L ttyAMA0 115200 vt100' >>/etc/inittab;
        rc-update add bootmisc boot;
        rc-update add devfs boot;
        rc-update add procfs boot;
        rc-update add sysfs boot;"

    log_info "[chroot] Configure users..."
    run_chroot "
        echo 'root:alpine' | chpasswd;
        useradd -m -G wheel -s /bin/bash alpine;
        echo 'alpine:alpine' | chpasswd;"

    log_info "[chroot] Configure sudoers..."
    run_chroot "sed -i 's/^# \(%wheel ALL=(ALL:ALL) NOPASSWD: ALL\)/\1/' /etc/sudoers"

    log_info "[chroot] Configure shared directory..."
    run_chroot "
        mkdir -p /share
        echo 'share /share 9p trans=virtio,version=9p2000.L,msize=262144,cache=mmap 0 0' >>/etc/fstab"

    sync

    log_success "Success: QEMU boot disk '$ALPINE_ROOTFS_OUTPUT' is ready."
}

main
