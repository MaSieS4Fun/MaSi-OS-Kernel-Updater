#!/usr/bin/env bash
# Copy reference DTB chain to device-tree/vendored/ (one-time).
# After this, builds do not need to extract ROCKNIX on every compile.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT

: "${CACHE_DIR:=${ROOT}/.cache}"
KERNEL="${1:-${ROCKNIX_KERNEL:-}}"

if [[ -z "${KERNEL}" ]]; then
    for c in \
        "${ROOT}/../Kernel-odin2/rocknix-boot-partition/KERNEL" \
        "${ROOT}/rocknix-reference/KERNEL"; do
        [[ -f "${c}" ]] && KERNEL="${c}" && break
    done
fi

[[ -f "${KERNEL}" ]] || {
    echo "Usage: $0 [/path/to/rocknix/KERNEL]" >&2
    exit 1
}

# shellcheck source=lib/dtb-chain/extract.sh
source "${ROOT}/lib/dtb-chain/extract.sh"

dest="${ROOT}/device-tree/vendored"
tmp="${CACHE_DIR}/dtb-chain/vendor-tmp"
rm -rf "${tmp}"
mkdir -p "${tmp}" "${dest}"

extract_dtb_chain_from_rocknix_kernel "${KERNEL}" "${tmp}" >/dev/null
cp -f "${tmp}"/slot-*.dtb "${dest}/"
cp -f "${tmp}/MANIFEST.txt" "${dest}/"

echo "Vendored: ${dest}/ ($(ls "${dest}"/slot-*.dtb | wc -l) slots)"
echo "Builds will use device-tree/vendored/ without re-reading ROCKNIX."
