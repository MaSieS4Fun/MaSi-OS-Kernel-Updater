#!/usr/bin/env bash
# Pre-build checks — autonomous build from public sources.
set -euo pipefail

preflight_sm8550_build() {
    local boot="${BOOT_KERNEL_PATH:-/boot/KERNEL}"
    local cfg="${BOOT_LINUXLOADER_CFG_PATH:-/boot/LinuxLoader.cfg}"
    local ok=1

    echo "==> Preflight" >&2

    if [[ -f "${cfg}" ]]; then
        echo "  OK  root UUID: ${cfg}" >&2
    elif [[ -f "${boot}" ]]; then
        echo "  OK  root UUID: ${boot}" >&2
    else
        echo "  !!  root UUID: need ${cfg} or ${boot} (or ROOT_UUID=)" >&2
        ok=0
    fi

    if [[ -f "${ROOT}/config/bootimg.abl.cfg" ]]; then
        echo "  OK  bootimg layout: config/bootimg.abl.cfg" >&2
    else
        echo "  !!  bootimg: missing config/bootimg.abl.cfg" >&2
        ok=0
    fi

    echo "  OK  DTB chain: reference slot order (config/dtb-chain.map)" >&2
    if [[ ! -f "${ROOT}/reference/armada-dtb-chain/slot-00.dtb" ]]; then
        if [[ -f "${ROOT}/armada-boot-partition/KERNEL" ]]; then
            echo "  ..  extracting reference/armada-dtb-chain from armada-boot-partition/KERNEL" >&2
            "${ROOT}/scripts/extract-armada-dtb-chain.sh" || ok=0
        else
            echo "  !!  missing reference/armada-dtb-chain (run ./scripts/extract-armada-dtb-chain.sh)" >&2
            ok=0
        fi
    else
        echo "  OK  reference/armada-dtb-chain/" >&2
    fi
    echo "  OK  firmware: ${FIRMWARE_SOURCE:-download} (${FIRMWARE_GIT_URL:-armbian/firmware})" >&2
    echo "  OK  initrd: ${INITRAMFS_PROFILE:-efi-clean} (scrubbed; gold off unless INITRAMFS_USE_GOLD=1)" >&2

    [[ "${ok}" -eq 1 ]] || {
        echo "  Fix the items above, then re-run ./make.sh" >&2
        return 1
    }
    echo >&2
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    export ROOT
    # shellcheck source=config/defaults.conf
    source "${ROOT}/config/defaults.conf"
    preflight_sm8550_build
fi
