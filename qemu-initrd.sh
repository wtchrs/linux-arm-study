#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

KERNEL="$SCRIPT_DIR/out-arm/arch/arm/boot/zImage"
INITRD="$SCRIPT_DIR/initramfs.cpio.gz"

qemu-system-arm \
    -machine 'virt' \
    -cpu 'cortex-a15' \
    -smp 4 \
    -m 2G \
    -kernel "$KERNEL" \
    -initrd "$INITRD" \
    -nographic \
    -append "console=ttyAMA0" \
    -fsdev local,id=fs0,path="$SCRIPT_DIR",security_model=none \
    -device virtio-9p-device,fsdev=fs0,mount_tag=share

# In arm virt machine, -virtio option does not work.
# -virtfs "local,path=$SCRIPT_DIR,security_model=none,mount_tag=share"
