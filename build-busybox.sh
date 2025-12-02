#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

SOURCE_PATH="$SCRIPT_DIR/busybox"
SOURCE_REPO=https://github.com/mirror/busybox
SOURCE_BRANCH=1_36_1

ARCH=arm
OUTPUT_PATH="$SCRIPT_DIR/out-busybox"
INITRAMFS_PATH="$SCRIPT_DIR/initramfs"

# Colors
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# ----------------------------
# Clone busybox
# ----------------------------
if [ ! -d "$SOURCE_PATH/.git" ]; then
    echo "${GREEN}[FETCH] Cloning BusyBox repository...${RESET}"
    git clone --depth=1 --branch="$SOURCE_BRANCH" "$SOURCE_REPO" "$SOURCE_PATH"
    (
        cd "$SOURCE_PATH"
        git apply "$SCRIPT_DIR/busybox-ncurses.patch"
    )
else
    echo "${YELLOW}[FETCH] BusyBox source already exists${RESET}"
fi

# ----------------------------
# Fetch toolchain
# ----------------------------
TOOLCHAIN_URL="https://developer.arm.com/-/media/Files/downloads/gnu/14.3.rel1/binrel/arm-gnu-toolchain-14.3.rel1-x86_64-arm-none-linux-gnueabihf.tar.xz"
TOOLCHAIN_ARCHIVE=$(basename "$TOOLCHAIN_URL")
TOOLCHAIN_PATH="$SCRIPT_DIR/toolchain"

if [ ! -d "$TOOLCHAIN_PATH" ]; then
    if [ ! -f "$TOOLCHAIN_ARCHIVE" ]; then
        echo "${GREEN}[FETCH] Downloading arm-none-linux-gnueabihf toolchain...${RESET}"
        curl -LJO "$TOOLCHAIN_URL"
    fi

    echo "${GREEN}[FETCH] Unarchiving arm-none-linux-gnueabihf toolchain...${RESET}"
    tar xvf "$TOOLCHAIN_ARCHIVE"
    UNARCHIVED_DIR=$(tar tf "$TOOLCHAIN_ARCHIVE" | sed -e 's@/.*@@' | uniq)
    mv "$SCRIPT_DIR/$UNARCHIVED_DIR" "$TOOLCHAIN_PATH"
else
    echo "${YELLOW}[FETCH] Toolchain already exists${RESET}"
fi

CROSS_COMPILE="$TOOLCHAIN_PATH/bin/arm-none-linux-gnueabihf-"

# Create output directory
if [ ! -d "$OUTPUT_PATH" ]; then
    echo "${GREEN}[SETUP] Creating output directory: $OUTPUT_PATH${RESET}"
    mkdir -p "$OUTPUT_PATH"
fi

# ----------------------------
# Helper function
# ----------------------------
run_make() {
    echo "${GREEN}[BUILD] Running make: $*${RESET}"
    make -C "$SOURCE_PATH" \
        O="$OUTPUT_PATH" \
        ARCH="$ARCH" \
        CROSS_COMPILE="$CROSS_COMPILE" \
        CONFIG_PREFIX="$INITRAMFS_PATH" \
        -j$(nproc) \
        "$@"
}

# ----------------------------
# Execute passed targets only
# ----------------------------
TARGETS="$@"
if [ ! -z "$TARGETS" ]; then
    run_make "$@"
    exit
fi

# ----------------------------
# Config and build busybox
# ----------------------------
echo "${GREEN}[CONFIG] Generating BusyBox default config...${RESET}"
run_make defconfig

echo "${GREEN}[CONFIG] Enabling static build...${RESET}"
echo CONFIG_STATIC=y >>"$OUTPUT_PATH/.config"
sed -i 's/^# CONFIG_STATIC .*$/CONFIG_STATIC=y/' "$OUTPUT_PATH/.config"
sed -i 's/^CONFIG_TC=y$/CONFIG_TC=n/' "$OUTPUT_PATH/.config"

echo "${GREEN}[CONFIG] Applying oldconfig...${RESET}"
run_make oldconfig

echo "${GREEN}[BUILD] Building BusyBox...${RESET}"
run_make all

echo "${GREEN}[INSTALL] Installing BusyBox to initramfs path: $INITRAMFS_PATH${RESET}"
run_make install

# ----------------------------
# Generate initramfs image
# ----------------------------
echo "${GREEN}[INITRAMFS] Preparing initramfs directory structure...${RESET}"
mkdir -p "$INITRAMFS_PATH"/{etc,proc,sys,mnt,share}

echo "${GREEN}[INITRAMFS] Creating init script...${RESET}"
cat <<'EOF' >"$INITRAMFS_PATH/init"
#!/bin/sh
/bin/mount -t devtmpfs devtmpfs /dev
/bin/mount -t proc none /proc
/bin/mount -t sysfs none /sys
/bin/mount -t 9p -o trans=virtio share /share
exec 0</dev/console
exec 1>/dev/console
exec 2>/dev/console
exec /bin/sh
EOF

chmod a+x "$INITRAMFS_PATH/init"

echo "${GREEN}[INITRAMFS] Packing initramfs into initramfs.cpio.gz...${RESET}"
(
    cd "$INITRAMFS_PATH"
    find . -print0 |
        cpio --null -ov --format=newc --owner=0:0 |
        gzip -9 >"$SCRIPT_DIR/initramfs.cpio.gz"
)

echo "${GREEN}[SUCCESS] Initramfs generation completed: $SCRIPT_DIR/initramfs.cpio.gz${RESET}"
