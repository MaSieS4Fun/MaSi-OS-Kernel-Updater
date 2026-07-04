#!/usr/bin/env bash
# Kernel_MaSi-OS — Analyze a ROCKNIX KERNEL (read-only) — DTBs, IKCFG, sizes.
# Does not copy blobs into the build; writes manifests to .cache/analysis/
#
# Usage: ./scripts/analyze-rocknix-reference.sh [KERNEL]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL="${1:-${ROCKNIX_KERNEL:-}}"
OUT="${ROOT}/.cache/analysis"
WORK="$(mktemp -d)"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

if [[ -z "$KERNEL" ]]; then
    for candidate in \
        "${ROOT}/../Kernel-odin2/rocknix-boot-partition/KERNEL" \
        "${ROOT}/rocknix-reference/KERNEL"; do
        [[ -f "$candidate" ]] && KERNEL="$candidate" && break
    done
fi

[[ -f "$KERNEL" ]] || {
    echo "Usage: $0 /path/to/rocknix-boot-partition/KERNEL" >&2
    exit 1
}

mkdir -p "$OUT"
command -v abootimg python3 sha256sum >/dev/null

echo "==> Reference: $KERNEL"
(
    cd "$WORK"
    abootimg -x "$KERNEL" >/dev/null 2>&1
)

[[ -f "$WORK/zImage" ]] || { echo "abootimg failed"; exit 1; }

python3 - "$WORK/zImage" "$OUT/dtb-manifest.txt" <<'PY'
import hashlib, struct, sys
from pathlib import Path

zpath, manifest = Path(sys.argv[1]), Path(sys.argv[2])
data = zpath.read_bytes()
magic = b"\xd0\x0d\xfe\xed"
idx = n = chain_start = None
rows = []
chain = bytearray()

while True:
    i = data.find(magic, idx)
    if i < 0:
        break
    if i + 8 <= len(data):
        size = struct.unpack(">I", data[i + 4 : i + 8])[0]
        if 0x1000 < size < 0x400000 and i + size <= len(data):
            blob = data[i : i + size]
            if chain_start is None:
                chain_start = i
            chain.extend(blob)
            hint = ""
            for needle in (b"ayn,odin2", b"ayn,odin2mini", b"ayn,odin2portal",
                           b"ayn,thor", b"retroidpocket,rp6", b"qcom,qcs8550"):
                if needle in blob:
                    hint = needle.decode()
                    break
            rows.append((n, size, hint, hashlib.sha256(blob).hexdigest()[:16]))
            n += 1
            idx = i + size
            continue
    idx = i + 4

lines = [
    f"# DTB chain analysis",
    f"# source zImage: {zpath}",
    f"# count: {n}",
    f"# chain_sha256: {hashlib.sha256(bytes(chain)).hexdigest()}",
    f"# chain_bytes: {len(chain)}",
    "",
    "slot\tsize\thint\tsha256_16",
]
for r in rows:
    lines.append(f"{r[0]}\t{r[1]}\t{r[2]}\t{r[3]}")
manifest.write_text("\n".join(lines) + "\n")
print(f"DTBs: {n} -> {manifest}")
PY

if [[ -f "$WORK/initrd.img" ]]; then
    du -h "$WORK/initrd.img" | awk '{print "initrd reference:", $0}'
    lsinitramfs "$WORK/initrd.img" 2>/dev/null | wc -l | awk '{print "initrd entries:", $1}'
fi

if python3 - "$WORK/zImage" "$OUT/rocknix-ikcfg.config" <<'PY'
import gzip, struct, sys
from pathlib import Path

src, out = Path(sys.argv[1]), Path(sys.argv[2])
data = src.read_bytes()
fdt = data.find(b"\xd0\x0d\xfe\xed")
if fdt < 0:
    sys.exit(1)
img = gzip.decompress(data[:fdt])
start, end = img.find(b"IKCFG_ST"), img.find(b"IKCFG_ED")
if start < 0 or end < 0:
    sys.exit(1)
text = gzip.decompress(img[start + 8 : end]).decode("utf-8", errors="replace")
out.write_text(text)
print(f"IKCFG -> {out} ({text.count(chr(10)) + 1} lines)")
PY
then
    grep -E 'SCHED_SMT|^CONFIG_PSI=|MMC_SDHCI_MSM_DOWNSTREAM|LONTIUM_LT8912B' \
        "$OUT/rocknix-ikcfg.config" || true
fi

echo "==> Listo. Ver $OUT/"
