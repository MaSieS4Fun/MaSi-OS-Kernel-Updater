#!/usr/bin/env bash
# Optional one-time setup after git clone (usually not required on Armbian handhelds).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT

echo "==> MaSi-OS Kernel Updater — first-run setup"
echo ""

# shellcheck source=config/defaults.conf
source "${ROOT}/config/defaults.conf"
# shellcheck source=lib/preflight.sh
source "${ROOT}/lib/preflight.sh"

if [[ -f /boot/KERNEL ]]; then
    n=0
    shopt -s nullglob
    for f in "${ROOT}/device-tree/vendored"/slot-*.dtb; do
        [[ -f "${f}" ]] && n=$((n + 1))
    done
    shopt -u nullglob
    if [[ "${n}" -lt 11 ]]; then
        echo "==> Caching DTB chain from /boot/KERNEL..."
        # shellcheck source=lib/dtb-chain/extract.sh
        source "${ROOT}/lib/dtb-chain/extract.sh"
        ROCKNIX_KERNEL=/boot/KERNEL "${ROOT}/scripts/vendor-dtb-chain.sh" /boot/KERNEL
    else
        echo "  DTB chain already vendored (${n} slots)"
    fi
else
    echo "  Skip DTB: no /boot/KERNEL (vendor manually later)"
fi

echo ""
if compgen -G "${ROOT}/reference/initrd.img-*" >/dev/null 2>&1; then
    echo "  Initrd reference already in reference/"
else
    echo "==> Initrd reference (optional, for gold profile)..."
    "${ROOT}/scripts/setup-reference-initrd.sh" || true
fi

echo ""
preflight_sm8550_build
echo "Ready: ./make.sh"
