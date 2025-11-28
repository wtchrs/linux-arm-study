#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

SOURCE_REPO=https://github.com/raspberrypi/linux
SOURCE_BRANCH=rpi-6.17.y
SOURCE_PATH="$SCRIPT_DIR/linux"

#ARCH=arm64
export ARCH=arm
export CROSS_COMPILE=
export LLVM=1
export EXTRAVERSION=-MY_CONFIG

OUTPUT_PATH="$SCRIPT_DIR/out-$ARCH"
BUILD_LOG="$OUTPUT_PATH/kernel_build.log"

export INSTALL_MOD_PATH=/mnt
export INSTALL_PATH=/mnt
