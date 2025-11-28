#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

KERNEL="$SCRIPT_DIR/out-arm/arch/arm/boot/zImage"
INITRD="$SCRIPT_DIR/initramfs.cpio.gz"
#IMG="$SCRIPT_DIR/2025-10-01-raspios-trixie-armhf-lite.img"

#qemu-system-arm \
#    -machine 'virt' \
#    -cpu 'cortex-a15' \
#    -smp 4 \
#    -m 2G \
#    -drive file="$IMG",if=none,format=raw,id=hd \
#    -device virtio-blk-device,drive=hd \
#    -device virtio-net-device,netdev=net \
#    -netdev user,id=net,hostfwd=tcp:127.0.0.1:2222-:22 \
#    -kernel "$KERNEL" \
#    -nographic \
#    -append "root=/dev/vda2 rw console=ttyAMA0" \
#    -virtfs "local,path=$SCRIPT_DIR,security_model=none,mount_tag=share"

qemu-system-arm \
    -machine 'virt' \
    -cpu 'cortex-a15' \
    -smp 4 \
    -m 2G \
    -kernel "$KERNEL" \
    -initrd "$INITRD" \
    -nographic \
    -append "console=ttyAMA0" \
    -virtfs "local,path=$SCRIPT_DIR,security_model=none,mount_tag=share"
