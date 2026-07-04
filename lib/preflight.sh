#!/usr/bin/env bash
# Pre-build checks for fresh clones on SM8550 Armbian devices.
set -euo pipefail

preflight_sm8550_build() {
    local boot="${BOOT_KERNEL_PATH:-/boot/KERNEL}"
    local cfg="${BOOT_LINUXLOADER_CFG_PATH:-/boot/LinuxLoader.cfg}"
    local n=0 f vendored="${ROOT}/device-tree/vendored"
    local ok=1

    echo "==> Preflight (fresh clone / any device)" >&2

    if [[ -f "${cfg}" ]]; then
        echo "  OK  root UUID: ${cfg}" >&2
    elif [[ -f "${boot}" ]]; then
        echo "  OK  root UUID: ${boot} (bootimg cmdline)" >&2
    else
        echo "  !!  missing ${cfg} or ${boot} — need root=UUID= source" >&2
        ok=0
    fi

    # shellcheck source=lib/cmdline.sh
    source "${ROOT}/lib/cmdline.sh"
    local cfg_initrd=""
    cfg_initrd="$(read_initrd_path_from_linuxloader_cfg 2>/dev/null || true)"

    if [[ -f "${boot}" ]]; then
        echo "  OK  boot template: ${boot} (DTB extract + bootimg layout)" >&2
    else
        echo "  !!  missing ${boot} — need ABL KERNEL on /boot for DTB chain and bootimg" >&2
        ok=0
    fi

    shopt -s nullglob
    for f in "${vendored}"/slot-*.dtb; do
        [[ -f "${f}" ]] && n=$((n + 1))
    done
    shopt -u nullglob

    if [[ "${n}" -ge 11 ]]; then
        echo "  OK  DTB chain: device-tree/vendored/ (${n} slots)" >&2
    elif [[ -f "${boot}" ]]; then
        echo "  OK  DTB chain: will extract from ${boot} on first build" >&2
    else
        echo "  !!  DTB chain: run ./scripts/vendor-dtb-chain.sh /path/to/KERNEL" >&2
        ok=0
    fi

    if [[ -n "${GOLD_INITRD_REF:-}" && -f "${GOLD_INITRD_REF}" ]] \
        || compgen -G "${ROOT}/reference/initrd.img-*" >/dev/null 2>&1 \
        || [[ -n "${cfg_initrd}" && -f "${cfg_initrd}" ]] \
        || compgen -G "/boot/initrd.img-*edge-sm8550*" >/dev/null 2>&1 \
        || compgen -G "/boot/initrd.img-*" >/dev/null 2>&1 \
        || [[ -f "${boot}" ]]; then
        echo "  OK  initrd: gold profile (LinuxLoader.cfg, /boot, or KERNEL bootimg)" >&2
    else
        echo "  OK  initrd: will use efi-clean fallback (no firmware in initrd)" >&2
        echo "      tip: ./scripts/setup-reference-initrd.sh for gold (~47 MB)" >&2
    fi

    if [[ -d /usr/lib/firmware/qcom/sm8550 || -d /lib/firmware/qcom/sm8550 ]]; then
        echo "  OK  host firmware: qcom/sm8550 present (output/firmware/)" >&2
    else
        echo "  !!  host firmware: install Armbian firmware before build" >&2
        ok=0
    fi

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
