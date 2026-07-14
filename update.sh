#!/usr/bin/env bash
# Install a MaSi-OS build on the system (backup → clean install → optional reboot).
#
# Usage:
#   sudo ./update.sh
#   UPDATE_BUILD=output/7.0.14-edge-sm8550-masi sudo ./update.sh
#   SKIP_REBOOT=1 sudo ./update.sh
#
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    exec sudo -- "$0" "$@"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ROOT
export OUTPUT_DIR="${ROOT}/output"

# shellcheck source=config/defaults.conf
source "${ROOT}/config/defaults.conf"
# shellcheck source=lib/install.sh
source "${ROOT}/lib/install.sh"

install_system_paths

echo "============================================================"
echo "  Kernel_MaSi-OS — Install"
echo "  Backup → output/old_kernel/  |  Clean install"
echo "============================================================"
echo ""
echo "Running kernel: $(uname -r)"
echo ""

install_pick_build || exit 1
build="${SELECTED_INSTALL_BUILD}"
release="$(install_resolve_release "${build}")" || exit 1

echo "Build to install: ${build}"
echo "  boot/KERNEL          → ${INSTALL_BOOT_DST}/  (microSD root UUID)"
echo "  firmware/        → ${INSTALL_FIRMWARE_DST}/  (full replace)"
echo "  modules/${release}/ → ${INSTALL_MODULES_DST}/  (full replace)"
echo "  audio stack      → modules-load.d, modprobe.d, masi-qcom-audio.service"
echo "  deep suspend     → sleep.conf.d + logind (if SUSPEND_DEEP=1 at build)"
echo "  UFS install      → /usr/lib/masi/ufs-linux/  (sudo masi-install-to-ufs)"
echo ""
echo "Current system will be saved to: ${OUTPUT_DIR}/old_kernel/"
echo "(owned by your user after backup — safe to delete without sudo)"
echo ""

if [[ -t 0 ]]; then
    read -r -p "Continue with backup and install? [y/N] " ans
    [[ "${ans,,}" == "y" ]] || { echo "Cancelled."; exit 0; }
fi

install_backup_running
install_from_build "${build}"
install_prompt_reboot
