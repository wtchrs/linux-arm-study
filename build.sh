#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/env.sh"

#----------------------------------------
# Colors
#----------------------------------------

RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# ---------------------------------------------------------
# Trap Error Handling
# ---------------------------------------------------------

last_cmd=""
current_cmd=""
trap 'last_cmd=$current_cmd; current_cmd=$BASH_COMMAND' DEBUG

cleanup() {
    :
}

error_handler() {
    local exit_code=$?
    local line_no=$1

    cat <<EOF

${RED}${BOLD}[ERROR] Build script failed${RESET}
  - Line        : $line_no
  - Exit code   : $exit_code
  - Command     : $last_cmd
EOF

    cleanup
    exit "$exit_code"
}

trap 'error_handler $LINENO' ERR
trap cleanup EXIT

# ---------------------------------------------------------
# Architecture-specific settings
# ---------------------------------------------------------
case "$ARCH" in
arm64)
    DEFCONFIG_TARGET=bcm2711_defconfig
    IMAGE_TARGET=Image
    ;;
arm)
    DEFCONFIG_TARGET=bcm2709_defconfig
    IMAGE_TARGET=zImage
    ;;
*)
    echo "${RED}ARCH must be 'arm' or 'arm64'${RESET}"
    exit 1
    ;;
esac

MAKE_FLAGS="-C $SOURCE_PATH O=$OUTPUT_PATH EXTRAVERSION=$EXTRAVERSION"

BUILD_TARGETS="$IMAGE_TARGET modules dtbs"

# -------------------------------------------
# Utilities
# -------------------------------------------

print_env() {
    cat <<EOF
SOURCE_PATH   = $SOURCE_PATH
OUTPUT_PATH   = $OUTPUT_PATH
BUILD_LOG     = $BUILD_LOG
ARCH          = $ARCH
MAKE_FLAGS    = $MAKE_FLAGS
BUILD_TARGETS = $BUILD_TARGETS

EOF
}

print_usage() {
    cat <<EOF
${BOLD}Build script for Linux kernel${RESET}

${YELLOW}Usage:${RESET} $0 [target [args...]]

${BOLD}Targets (default: all):${RESET}
  ${GREEN}fetch${RESET}                   Clone kernel repository (if missing)
  ${GREEN}all${RESET}                     Build kernel, modules, dtbs
  ${GREEN}kernel${RESET}                  Build kernel only
  ${GREEN}modules${RESET}                 Build modules only
  ${GREEN}defconfig${RESET}               Generate default config + custom enables
  ${GREEN}menuconfig${RESET}              Launch menuconfig
  ${GREEN}olddefconfig${RESET}            Apply default answers to new options
  ${GREEN}preprocess <files...>${RESET}   Preprocess given targets
  ${GREEN}compile_commands${RESET}        Generate compile_commands.json
  ${GREEN}modules_install${RESET}         Install modules to INSTALL_MOD_PATH
  ${GREEN}install${RESET}                 Install kernel image and DTBs to INSTALL_PATH
  ${GREEN}clean${RESET}                   Remove build outputs
  ${GREEN}help${RESET}                    Show this help
EOF
}

run_make() {
    # Usage: run_make <make-targets...>
    make $MAKE_FLAGS -j"$(nproc)" "$@" 2>&1 | tee "$BUILD_LOG"
}

# -------------------------------------------
# Targets
# -------------------------------------------

fetch() {
    if [ -d "$SOURCE_PATH/.git" ]; then
        echo "${YELLOW}$SOURCE_PATH already exists${RESET}"
    else
        echo "${GREEN}Cloning kernel repository...${RESET}"
        git clone --depth=1 --branch "$SOURCE_BRANCH" "$SOURCE_REPO" "$SOURCE_PATH"
    fi
}

all() {
    echo "${GREEN}[BUILD] Building kernel, modules, dtbs...${RESET}"
    run_make $BUILD_TARGETS
}

kernel() {
    echo "${GREEN}[BUILD] Building kernel image...${RESET}"
    run_make "$IMAGE_TARGET"
}

modules() {
    echo "${GREEN}[BUILD] Building modules...${RESET}"
    run_make modules
}

compile_commands() {
    echo "${GREEN}[BUILD] Generating compile_commands.json...${RESET}"
    (
        cd "$OUTPUT_PATH"
        "$SOURCE_PATH/scripts/clang-tools/gen_compile_commands.py"
    )
    ln -sf "$OUTPUT_PATH/compile_commands.json" "$SOURCE_PATH/compile_commands.json"
}

olddefconfig() {
    echo "${GREEN}[CONFIG] Running olddefconfig...${RESET}"
    make $MAKE_FLAGS olddefconfig
}

defconfig() {
    local CONFIG_SCRIPT="$SOURCE_PATH/scripts/config"

    echo "${GREEN}[CONFIG] Generating defconfig...${RESET}"
    make $MAKE_FLAGS "$DEFCONFIG_TARGET"

    echo "${GREEN}[CONFIG] Applying custom config enables...${RESET}"
    "$CONFIG_SCRIPT" --file "$OUTPUT_PATH/.config" \
        --enable CONFIG_VIRTIO \
        --enable CONFIG_VIRTIO_BALLOON \
        --enable CONFIG_VIRTIO_BLK \
        --enable CONFIG_VIRTIO_MMIO \
        --enable CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES \
        --enable CONFIG_VIRTIO_NET \
        --enable CONFIG_FTRACE \
        --enable CONFIG_FUNCTION_TRACER \
        --enable CONFIG_DYNAMIC_FTRACE \
        --enable CONFIG_KPROBES

    olddefconfig
}

menuconfig() {
    echo "${YELLOW}[CONFIG] Launching menuconfig...${RESET}"
    make $MAKE_FLAGS menuconfig
}

preprocess() {
    if [ $# -eq 0 ]; then
        print_usage
        exit 1
    fi

    echo "${GREEN}PREPROCESS_TARGETS = $*${RESET}"
    make $MAKE_FLAGS -j"$(nproc)" "$@"
}

modules_install() {
    if [ -z "$INSTALL_MOD_PATH" ]; then
        echo "${RED}Error: INSTALL_MOD_PATH must be set${RESET}"
        exit 1
    fi

    echo "${GREEN}INSTALL_MOD_PATH = $INSTALL_MOD_PATH${RESET}"
    make $MAKE_FLAGS INSTALL_MOD_PATH="$INSTALL_MOD_PATH" modules_install
    echo "${GREEN}Modules are installed at $INSTALL_MOD_PATH${RESET}"
}

install_kernel() {
    local BUILD_BOOT_DIR="$OUTPUT_PATH/arch/$ARCH/boot"

    echo "${GREEN}[INSTALL] Installing kernel and DTBs...${RESET}"
    mkdir -p "$INSTALL_PATH/overlays"

    cp "$BUILD_BOOT_DIR/dts/broadcom/"*.dtb "$INSTALL_PATH/"
    cp "$BUILD_BOOT_DIR/dts/overlays/"*.dtb* "$INSTALL_PATH/overlays/"

    local OUT_IMG
    if [ "$ARCH" == "arm64" ]; then
        OUT_IMG="kernel8${EXTRAVERSION}.img"
        cp "$BUILD_BOOT_DIR/Image" "$INSTALL_PATH/$OUT_IMG"
    else
        OUT_IMG="kernel7${EXTRAVERSION}.img"
        cp "$BUILD_BOOT_DIR/zImage" "$INSTALL_PATH/$OUT_IMG"
    fi

    echo "${GREEN}Kernel and DTBs are installed at $INSTALL_PATH ($OUT_IMG)${RESET}"
}

clean() {
    rm -rf "$OUTPUT_PATH"
    echo "${YELLOW}Cleaned: $OUTPUT_PATH${RESET}"
}

# -------------------------------------------
# Target dispatch
# -------------------------------------------

TARGET="${1:-}"
shift || true

print_env

if [ -z "$TARGET" ]; then
    all
    exit 0
fi

case "$TARGET" in
all) all ;;
kernel) kernel ;;
modules) modules ;;
defconfig) defconfig ;;
menuconfig) menuconfig ;;
olddefconfig) olddefconfig ;;
fetch) fetch ;;
preprocess) preprocess "$@" ;;
compile_commands) compile_commands ;;
modules_install) modules_install ;;
install) install_kernel ;;
clean) clean ;;
help) print_usage ;;
*)
    print_usage
    exit 1
    ;;
esac
