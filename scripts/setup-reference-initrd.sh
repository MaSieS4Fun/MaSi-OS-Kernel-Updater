#!/usr/bin/env bash
# Copy a working initrd from /boot into reference/ for INITRAMFS_PROFILE=gold.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF="${ROOT}/reference"
mkdir -p "${REF}"

pick_source() {
    local candidate cfg_initrd

    if [[ -n "${1:-}" && -f "${1}" ]]; then
        echo "${1}"
        return 0
    fi

    # shellcheck source=lib/cmdline.sh
    source "${ROOT}/lib/cmdline.sh"
    if cfg_initrd="$(read_initrd_path_from_linuxloader_cfg 2>/dev/null || true)"; then
        [[ -n "${cfg_initrd}" && -f "${cfg_initrd}" ]] && {
            echo "${cfg_initrd}"
            return 0
        }
    fi

    shopt -s nullglob
    for candidate in \
        /boot/initrd.img-*edge-sm8550* \
        /boot/initrd.img-*; do
        [[ -f "${candidate}" ]] || continue
        echo "${candidate}"
        shopt -u nullglob
        return 0
    done
    shopt -u nullglob
    return 1
}

src="$(pick_source "${1:-}")" || {
    echo "No initrd found under /boot/." >&2
    echo "" >&2
    echo "Usage: $0 [/path/to/initrd.img-*]" >&2
    echo "  Or copy manually: cp /path/to/initrd.img reference/" >&2
    echo "  Or: GOLD_INITRD_REF=/path/to/initrd.img ./make.sh" >&2
    exit 1
}

base="$(basename "${src}")"
dest="${REF}/${base}"

cp -f "${src}" "${dest}"
echo "Reference initrd installed:"
echo "  ${dest} ($(du -h "${dest}" | cut -f1))"
echo ""
echo "Build with: INITRAMFS_PROFILE=gold ./make.sh"
