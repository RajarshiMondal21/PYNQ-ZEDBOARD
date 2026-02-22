# PYNQ-ZEDBOARD

Automated build script and board configuration to create a **PYNQ 3.1.0** SD-card image for the [Avnet ZedBoard](https://www.avnet.com/wps/portal/us/products/avnet-boards/avnet-board-families/zedboard/) (Xilinx Zynq-7000).

---

## Repository layout

```
.
├── build_pynq_zedboard.sh   # Main automated build script
├── Pynq-ZED/
│   └── Pynq-ZED.spec        # PYNQ sdbuild board specification
└── README.md
```

---

## Host prerequisites

Install the following tools on your Ubuntu 20.04 / 22.04 x86-64 build machine **before** running the script:

| Tool | Version | Notes |
|------|---------|-------|
| Xilinx Vivado | 2022.1 | With Zynq-7000 device support |
| Xilinx Petalinux | 2022.1 | |
| Xilinx Vitis | 2022.1 | |
| QEMU (cross) | — | Expected at `/opt/qemu/bin` |
| crosstool-NG | — | Expected at `/opt/crosstool-ng/bin` |
| liblzma-dev | — | `sudo apt-get install liblzma-dev` |

Allow passwordless sudo for the build user (required by PYNQ sdbuild):

```bash
sudo visudo
# Add at the end of the file:
your_username ALL=(ALL) NOPASSWD: ALL
```

Run the PYNQ host-setup script once to install additional build dependencies:

```bash
# Done automatically by build_pynq_zedboard.sh, but can be run standalone:
bash PYNQ/sdbuild/scripts/setup_host.sh
```

---

## Quick start

```bash
# Clone this repository
git clone https://github.com/RajarshiMondal21/PYNQ-ZEDBOARD.git
cd PYNQ-ZEDBOARD

# Make the script executable
chmod +x build_pynq_zedboard.sh

# Run the full automated build
./build_pynq_zedboard.sh
```

The finished image is written to:

```
$HOME/pynq_build/PYNQ/sdbuild/output/Pynq-ZED-3.1.0.img
```

Flash it to a micro-SD card with `dd` or [balenaEtcher](https://etcher.balena.io/).

---

## Environment variables

Override any default path by exporting the corresponding variable before running the script:

| Variable | Default | Description |
|----------|---------|-------------|
| `WORK_DIR` | `$HOME/pynq_build` | Top-level working directory |
| `VIVADO_SETTINGS` | `/opt/Xilinx/Vivado/2022.1/settings64.sh` | Vivado environment script |
| `PETALINUX_SETTINGS` | `/opt/petalinux/2022.1/settings.sh` | Petalinux environment script |
| `VITIS_SETTINGS` | `/opt/Xilinx/Vitis/2022.1/settings64.sh` | Vitis environment script |
| `QEMU_BIN` | `/opt/qemu/bin` | QEMU binaries directory |
| `CROSSTOOL_BIN` | `/opt/crosstool-ng/bin` | crosstool-NG binaries directory |

Example:

```bash
WORK_DIR=/scratch/pynq ./build_pynq_zedboard.sh
```

---

## What the script does (step by step)

1. **Verify host tools** – checks that `vivado`, `petalinux-create`, `wget`, `tar`, and `git` are on `PATH`.
2. **Download ZedBoard BSP** – fetches the Avnet/Digilent ZedBoard v2021.2 BSP from the Xilinx download server.
   > ⚠️ The Xilinx download may require a free account. If the automated download fails, download `avnet-digilent-zedboard-v2021.2-final.bsp` manually, place it in `$WORK_DIR`, and re-run the script.
3. **Upgrade Vivado project and export XSA** – opens the hardware project from the BSP in batch-mode Vivado 2022.1, upgrades all IPs, runs implementation to generate a bitstream, then exports `zedboard_2022.1.xsa`.
4. **Build Petalinux project** – creates a Petalinux 2022.1 Zynq project, configures it with the exported XSA, builds the project, and packages it as `zedboard_2022.1.bsp`.
5. **Clone PYNQ** – clones the [Xilinx/PYNQ](https://github.com/Xilinx/PYNQ) repository and checks out tag `v3.1.0`.
6. **Install host prerequisites** – installs `liblzma-dev` and runs `setup_host.sh`.
7. **Download PYNQ rootfs and source distribution** – fetches `jammy.arm.3.1.0.tar.gz` (pre-built rootfs) and `pynq-3.1.0.tar.gz` (Python source distribution).
8. **Set up boards directory** – copies the `Pynq-ZED.spec` file and the packaged BSP into the boards directory used by sdbuild.
9. **Build PYNQ image** – invokes `make` inside `PYNQ/sdbuild` with all required variables to produce the final SD-card image.

---

## Board specification (`Pynq-ZED/Pynq-ZED.spec`)

```makefile
ARCH_Pynq-ZED := arm
BSP_Pynq-ZED := zedboard_2022.1.bsp
BITSTREAM_Pynq-ZED := base/base.bit
FPGA_MANAGER_Pynq-ZED := 1

STAGE4_PACKAGES_Pynq-ZED := pynq ethernet xrt uart pandas opencv jupyter ssl
```

---

## References

- [PYNQ documentation](http://www.pynq.io)
- [Xilinx/PYNQ GitHub](https://github.com/Xilinx/PYNQ)
- [Avnet ZedBoard product page](https://www.avnet.com/wps/portal/us/products/avnet-boards/avnet-board-families/zedboard/)
- [Petalinux 2022.1 user guide (UG1144)](https://docs.xilinx.com/r/en-US/ug1144-petalinux-tools-reference-guide)
