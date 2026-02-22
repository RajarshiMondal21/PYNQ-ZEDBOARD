#!/usr/bin/env bash
# =============================================================================
# build_pynq_zedboard.sh
#
# Automated script to build a PYNQ 3.1.0 image for the Avnet ZedBoard.
#
# Prerequisites (must be installed on the build host before running):
#   - Xilinx Vivado 2022.1
#   - Xilinx Petalinux 2022.1
#   - Xilinx Vitis 2022.1
#   - QEMU cross-compiled binaries at /opt/qemu/bin
#   - crosstool-NG at /opt/crosstool-ng/bin
#   - sudo apt-get install liblzma-dev   (run once manually)
#
# Usage:
#   chmod +x build_pynq_zedboard.sh
#   ./build_pynq_zedboard.sh
#
# Outputs:
#   $WORK_DIR/PYNQ/sdbuild/output/Pynq-ZED-3.1.0.img
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configurable variables – override via environment before running the script
# ---------------------------------------------------------------------------
WORK_DIR="${WORK_DIR:-$HOME/pynq_build}"
VIVADO_SETTINGS="${VIVADO_SETTINGS:-/opt/Xilinx/Vivado/2022.1/settings64.sh}"
PETALINUX_SETTINGS="${PETALINUX_SETTINGS:-/opt/petalinux/2022.1/settings.sh}"
VITIS_SETTINGS="${VITIS_SETTINGS:-/opt/Xilinx/Vitis/2022.1/settings64.sh}"
QEMU_BIN="${QEMU_BIN:-/opt/qemu/bin}"
CROSSTOOL_BIN="${CROSSTOOL_BIN:-/opt/crosstool-ng/bin}"

# PYNQ 3.1.0 release artifacts
PYNQ_REPO_URL="https://github.com/Xilinx/PYNQ.git"
PYNQ_VERSION="v3.1.0"
PYNQ_SDIST_URL="https://github.com/Xilinx/PYNQ/releases/download/${PYNQ_VERSION}/pynq-3.1.0.tar.gz"
PYNQ_ROOTFS_URL="https://bit.ly/pynq_arm_v3_1"

# ZedBoard BSP source (Avnet 2021.2 BSP – upgraded to 2022.1 in this script).
# NOTE: The Xilinx download portal requires a free account. The wget below may
# download an HTML login page rather than the actual archive. If the tar step
# fails, download the file manually from the Xilinx download centre, save it as
# $WORK_DIR/avnet-digilent-zedboard-v2021.2-final.bsp, and re-run the script.
BSP_URL="https://www.xilinx.com/member/forms/download/xef.html?filename=avnet-digilent-zedboard-v2021.2-final.bsp"
BSP_FILENAME="avnet-digilent-zedboard-v2021.2-final.bsp"
PETALINUX_PROJECT="zedboard"
PETALINUX_BSP="zedboard_2022.1.bsp"

BOARD_NAME="Pynq-ZED"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
log()  { echo "[$(date '+%H:%M:%S')] $*"; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

check_tool() {
    command -v "$1" >/dev/null 2>&1 || die "'$1' not found. Please install it before running this script."
}

# ---------------------------------------------------------------------------
# Step 0 – verify host tools
# ---------------------------------------------------------------------------
log "=== Step 0: Verifying host tools ==="
check_tool wget
check_tool tar
check_tool vivado
check_tool petalinux-create
check_tool git

# ---------------------------------------------------------------------------
# Step 1 – set up working directory
# ---------------------------------------------------------------------------
log "=== Step 1: Creating work directory: $WORK_DIR ==="
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# ---------------------------------------------------------------------------
# Step 2 – download and extract the ZedBoard BSP
# ---------------------------------------------------------------------------
log "=== Step 2: Downloading ZedBoard BSP ==="
if [[ ! -f "$BSP_FILENAME" ]]; then
    wget -O "$BSP_FILENAME" "$BSP_URL" \
        || die "Failed to download BSP. Xilinx downloads may require an account; download '$BSP_FILENAME' manually and place it in $WORK_DIR."
fi

log "Extracting BSP..."
tar -xf "$BSP_FILENAME" \
    || die "Failed to extract BSP. The file may be an HTML login page. Download '$BSP_FILENAME' manually from the Xilinx download centre and place it in $WORK_DIR."

# The hardware project lives in the /hardware/ sub-directory of the extracted BSP.
# Search without a hard depth limit so the script remains correct if the BSP
# directory structure changes in future releases.
HW_PROJECT_DIR="$(find "$WORK_DIR" -name "*.xpr" -print -quit | xargs dirname 2>/dev/null || true)"
[[ -n "$HW_PROJECT_DIR" ]] || die "Could not locate Vivado project (.xpr) inside the extracted BSP."
log "Found hardware project at: $HW_PROJECT_DIR"

# ---------------------------------------------------------------------------
# Step 3 – upgrade Vivado project to 2022.1 and export XSA
# ---------------------------------------------------------------------------
log "=== Step 3: Upgrading Vivado project and exporting XSA ==="
# shellcheck source=/dev/null
source "$VIVADO_SETTINGS"

XSA_PATH="$WORK_DIR/zedboard_2022.1.xsa"
XPR_FILE="$(find "$HW_PROJECT_DIR" -name "*.xpr" | head -1)"

TCL_SCRIPT="$(mktemp --suffix=.tcl)"
cat > "$TCL_SCRIPT" <<'TCL'
# Open the project (upgrade silently)
open_project [lindex $argv 0]
upgrade_ip [get_ips]
# Regenerate all IP output products
generate_target all [get_ips]
# Implement design to generate bitstream
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
# Export hardware including bitstream
set xsa_path [lindex $argv 1]
write_hw_platform -fixed -include_bit -force -file $xsa_path
close_project
TCL

vivado -mode batch -source "$TCL_SCRIPT" \
       -tclargs "$XPR_FILE" "$XSA_PATH" \
    || die "Vivado upgrade/export failed."
rm -f "$TCL_SCRIPT"

log "XSA exported to: $XSA_PATH"

# ---------------------------------------------------------------------------
# Step 4 – create and build Petalinux project
# ---------------------------------------------------------------------------
log "=== Step 4: Building Petalinux project ==="
# shellcheck source=/dev/null
source "$PETALINUX_SETTINGS"

if [[ -d "$WORK_DIR/$PETALINUX_PROJECT" ]]; then
    log "Removing existing Petalinux project directory..."
    rm -rf "$WORK_DIR/$PETALINUX_PROJECT"
fi

cd "$WORK_DIR"
petalinux-create -t project --template zynq --name "$PETALINUX_PROJECT"
cd "$WORK_DIR/$PETALINUX_PROJECT"

petalinux-config --silentconfig --get-hw-description="$XSA_PATH"
petalinux-build
petalinux-package --bsp -o "$WORK_DIR/$PETALINUX_BSP"

log "Petalinux BSP packaged: $WORK_DIR/$PETALINUX_BSP"

# ---------------------------------------------------------------------------
# Step 5 – clone PYNQ repository (tag v3.1.0)
# ---------------------------------------------------------------------------
log "=== Step 5: Cloning PYNQ repository ($PYNQ_VERSION) ==="
cd "$WORK_DIR"
if [[ -d "PYNQ" ]]; then
    log "PYNQ repo already present – fetching updates..."
    git -C PYNQ fetch --tags
else
    git clone "$PYNQ_REPO_URL" PYNQ
fi
git -C PYNQ checkout "$PYNQ_VERSION"

# ---------------------------------------------------------------------------
# Step 6 – install host prerequisites and run setup_host.sh
# ---------------------------------------------------------------------------
log "=== Step 6: Installing host prerequisites ==="
if ! dpkg -s liblzma-dev >/dev/null 2>&1; then
    log "Installing liblzma-dev (requires sudo)..."
    sudo apt-get install -y liblzma-dev
else
    log "liblzma-dev already installed, skipping."
fi

log "Running PYNQ host setup script..."
bash "$WORK_DIR/PYNQ/sdbuild/scripts/setup_host.sh"

# ---------------------------------------------------------------------------
# Step 7 – download PYNQ rootfs and source distribution
# ---------------------------------------------------------------------------
log "=== Step 7: Downloading PYNQ 3.1.0 rootfs and source distribution ==="
cd "$WORK_DIR"

PYNQ_ROOTFS_FILE="jammy.arm.3.1.0.tar.gz"
PYNQ_SDIST_FILE="pynq-3.1.0.tar.gz"

if [[ ! -f "$PYNQ_ROOTFS_FILE" ]]; then
    wget -O "$PYNQ_ROOTFS_FILE" "$PYNQ_ROOTFS_URL" \
        || die "Failed to download PYNQ rootfs. Download manually from $PYNQ_ROOTFS_URL and place as $WORK_DIR/$PYNQ_ROOTFS_FILE."
fi

if [[ ! -f "$PYNQ_SDIST_FILE" ]]; then
    wget -O "$PYNQ_SDIST_FILE" "$PYNQ_SDIST_URL" \
        || die "Failed to download PYNQ source distribution."
fi

# ---------------------------------------------------------------------------
# Step 8 – set up boards directory with ZedBoard spec
# ---------------------------------------------------------------------------
log "=== Step 8: Setting up boards directory ==="
BOARDS_DIR="$WORK_DIR/boards"
mkdir -p "$BOARDS_DIR/$BOARD_NAME"

# Copy spec file from this repository
SPEC_SRC="$SCRIPT_DIR/$BOARD_NAME/$BOARD_NAME.spec"
if [[ -f "$SPEC_SRC" ]]; then
    cp "$SPEC_SRC" "$BOARDS_DIR/$BOARD_NAME/$BOARD_NAME.spec"
else
    # Write spec inline as fallback
    cat > "$BOARDS_DIR/$BOARD_NAME/$BOARD_NAME.spec" <<'SPEC'
ARCH_Pynq-ZED := arm
BSP_Pynq-ZED := zedboard_2022.1.bsp
BITSTREAM_Pynq-ZED := base/base.bit
FPGA_MANAGER_Pynq-ZED := 1

STAGE4_PACKAGES_Pynq-ZED := pynq ethernet xrt uart pandas opencv jupyter ssl
SPEC
fi

# Copy the Petalinux BSP into the board directory so PYNQ sdbuild can find it
cp "$WORK_DIR/$PETALINUX_BSP" "$BOARDS_DIR/$BOARD_NAME/$PETALINUX_BSP"

# ---------------------------------------------------------------------------
# Step 9 – build PYNQ image
# ---------------------------------------------------------------------------
log "=== Step 9: Building PYNQ 3.1.0 image for $BOARD_NAME ==="

# shellcheck source=/dev/null
source "$PETALINUX_SETTINGS"
# shellcheck source=/dev/null
source "$VITIS_SETTINGS"

export PATH="$QEMU_BIN:$CROSSTOOL_BIN:$PATH"

cd "$WORK_DIR/PYNQ/sdbuild"

make \
    PYNQ_SDIST="$WORK_DIR/$PYNQ_SDIST_FILE" \
    PYNQ_ROOTFS="$WORK_DIR/$PYNQ_ROOTFS_FILE" \
    BOARDDIR="$BOARDS_DIR" \
    BOARDS="$BOARD_NAME"

log "=== Build complete! ==="
log "Output image: $WORK_DIR/PYNQ/sdbuild/output/${BOARD_NAME}-3.1.0.img"
