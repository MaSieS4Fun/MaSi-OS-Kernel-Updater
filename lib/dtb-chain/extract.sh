#!/usr/bin/env bash
# Extract 11 DTBs from a ROCKNIX zImage → slot-NN.dtb
set -euo pipefail

extract_dtb_chain_from_zimage() {
    local zimage="$1" dest_dir="$2"

    [[ -f "${zimage}" ]] || {
        echo "Missing zImage: ${zimage}" >&2
        return 1
    }
    mkdir -p "${dest_dir}"

    python3 - "${zimage}" "${dest_dir}" <<'PY'
import hashlib, struct, sys
from pathlib import Path

zpath, outdir = Path(sys.argv[1]), Path(sys.argv[2])
data = zpath.read_bytes()
magic = b"\xd0\x0d\xfe\xed"
idx = n = 0
manifest = []

while True:
    i = data.find(magic, idx)
    if i < 0:
        break
    if i + 8 <= len(data):
        size = struct.unpack(">I", data[i + 4 : i + 8])[0]
        if 0x1000 < size < 0x400000 and i + size <= len(data):
            blob = data[i : i + size]
            slot = outdir / f"slot-{n:02d}.dtb"
            slot.write_bytes(blob)
            hint = ""
            for needle in (
                b"ayn,odin2mini", b"ayn,odin2portal", b"ayn,odin2", b"ayn,thor",
                b"retroidpocket,rp6", b"qcom,qcs8550",
            ):
                if needle in blob:
                    hint = needle.decode()
                    break
            manifest.append((n, size, hint, hashlib.sha256(blob).hexdigest()[:16]))
            n += 1
            idx = i + size
            continue
    idx = i + 4

if n == 0:
    sys.stderr.write("No DTBs found in zImage\n")
    sys.exit(1)

lines = [
    "# DTB chain extract",
    f"# source: {zpath}",
    f"# count: {n}",
    "",
    "slot\tsize\thint\tsha256_16",
]
for row in manifest:
    lines.append(f"{row[0]}\t{row[1]}\t{row[2]}\t{row[3]}")
(outdir / "MANIFEST.txt").write_text("\n".join(lines) + "\n")
print(n)
PY
}

extract_dtb_chain_from_rocknix_kernel() {
    local kernel_blob="$1" dest_dir="$2" work count

    kernel_blob="$(readlink -f "${kernel_blob}")"
    [[ -f "${kernel_blob}" ]] || {
        echo "Missing ROCKNIX KERNEL: ${kernel_blob}" >&2
        return 1
    }
    command -v abootimg >/dev/null 2>&1 || {
        echo "Install: sudo apt install abootimg" >&2
        return 1
    }

    work="$(mktemp -d)"
    (
        cd "${work}"
        abootimg -x "${kernel_blob}" >/dev/null 2>&1
    )
    [[ -f "${work}/zImage" ]] || {
        rm -rf "${work}"
        echo "abootimg failed on ${kernel_blob}" >&2
        return 1
    }

    echo "==> Extracting DTB chain (ROCKNIX reference)..." >&2
    count="$(extract_dtb_chain_from_zimage "${work}/zImage" "${dest_dir}")"
    rm -rf "${work}"
    echo "  ${count} slot(s) → ${dest_dir}/" >&2
    export DTB_CHAIN_REFERENCE_COUNT="${count}"
    [[ "${count}" -ge 11 ]] || {
        echo "Expected ≥11 DTBs; found ${count}" >&2
        return 1
    }
    echo "${count}"
}

resolve_rocknix_kernel_path() {
    local candidate
    if [[ -n "${ROCKNIX_KERNEL:-}" && -f "${ROCKNIX_KERNEL}" ]]; then
        readlink -f "${ROCKNIX_KERNEL}"
        return 0
    fi
    for candidate in \
        "${BOOT_KERNEL_PATH:-/boot/KERNEL}" \
        /boot/KERNEL \
        "${ROOT}/device-tree/reference/KERNEL" \
        "${ROOT}/rocknix-reference/KERNEL"; do
        [[ -f "${candidate}" ]] && readlink -f "${candidate}" && return 0
    done
    return 1
}

ensure_reference_dtb_chain() {
    local ref_dir="${DTB_REFERENCE_DIR:-${CACHE_DIR}/dtb-chain/reference}"
    local vendored="${ROOT}/device-tree/vendored"
    local kernel n=0 f

    mkdir -p "${ref_dir}"

    for f in "${vendored}"/slot-*.dtb; do
        [[ -f "${f}" ]] || continue
        n=$((n + 1))
    done
    if [[ "${n}" -ge 11 ]]; then
        echo "==> DTB chain: device-tree/vendored/ (${n} slots)" >&2
        rm -f "${ref_dir}"/slot-*.dtb
        cp -f "${vendored}"/slot-*.dtb "${ref_dir}/"
        cp -f "${vendored}/MANIFEST.txt" "${ref_dir}/" 2>/dev/null || true
        DTB_REFERENCE_DIR="${ref_dir}"
        export DTB_REFERENCE_DIR
        return 0
    fi

    if [[ -f "${ref_dir}/slot-00.dtb" && -f "${ref_dir}/slot-10.dtb" ]]; then
        echo "==> DTB chain: cache ${ref_dir}" >&2
        DTB_REFERENCE_DIR="${ref_dir}"
        export DTB_REFERENCE_DIR
        return 0
    fi

    kernel="$(resolve_rocknix_kernel_path)" || {
        echo "No vendored DTB chain and no ROCKNIX_KERNEL." >&2
        echo "  Options:" >&2
        echo "    ROCKNIX_KERNEL=/boot/KERNEL ./make.sh" >&2
        echo "    ./scripts/vendor-dtb-chain.sh /boot/KERNEL" >&2
        return 1
    }

    extract_dtb_chain_from_rocknix_kernel "${kernel}" "${ref_dir}" >/dev/null
    DTB_REFERENCE_DIR="${ref_dir}"
    export DTB_REFERENCE_DIR
}
