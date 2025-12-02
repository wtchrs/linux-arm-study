#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

RASPBERRY_PI=0

if [ "$RASPBERRY_PI" == 1 ]; then
    SOURCE_REPO=https://github.com/raspberrypi/linux
    SOURCE_BRANCH=rpi-6.18.y
else
    SOURCE_REPO=https://github.com/torvalds/linux
    SOURCE_BRANCH=v6.18
fi

SOURCE_PATH="$SCRIPT_DIR/linux"

#ARCH=arm64
export ARCH=arm
export CROSS_COMPILE=
export LLVM=1
export EXTRAVERSION=-MY_CONFIG

OUTPUT_PATH="$SCRIPT_DIR/out-$ARCH"
BUILD_LOG="$OUTPUT_PATH/kernel_build.log"

export INSTALL_MOD_PATH="$SCRIPT_DIR/initramfs"
export INSTALL_PATH=/mnt
