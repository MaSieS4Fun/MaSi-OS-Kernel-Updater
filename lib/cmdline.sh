#!/usr/bin/env bash
set -euo pipefail

# Root UUID: /boot/LinuxLoader.cfg first, then /boot/KERNEL bootimg cmdline.
BOOT_LINUXLOADER_CFG_PATH="${BOOT_LINUXLOADER_CFG_PATH:-/boot/LinuxLoader.cfg}"
BOOT_KERNEL_PATH="${BOOT_KERNEL_PATH:-/boot/KERNEL}"
# Set by resolve_root_uuid on success (source path or "ROOT_UUID override")
ROOT_UUID_SOURCE="${ROOT_UUID_SOURCE:-}"
RESOLVED_ROOT_UUID="${RESOLVED_ROOT_UUID:-}"

read_cmdline_from_bootimg() {
    local kernel="${1:-${BOOT_KERNEL_PATH}}"
    [[ -f "${kernel}" ]] || return 1

    if command -v abootimg >/dev/null 2>&1; then
        abootimg -i "${kernel}" 2>/dev/null | sed -n 's/^\* cmdline = //p' | head -1
        return 0
    fi

    python3 - "${kernel}" <<'PY'
import struct, sys
from pathlib import Path

p = Path(sys.argv[1])
data = p.read_bytes()
if data[:8] != b"ANDROID!":
    sys.exit(1)
cmd = data[0x40 : 0x40 + 512].split(b"\x00")[0].decode("ascii", errors="replace")
print(cmd)
PY
}

extract_root_uuid_from_cmdline() {
    local cmdline="$1"
    python3 - "${cmdline}" <<'PY'
import re, sys
m = re.search(r"root=UUID=([0-9a-fA-F-]{36})", sys.argv[1])
if m:
    print(m.group(1))
PY
}

read_cmdline_from_linuxloader_cfg() {
    read_linuxloader_linux_field cmdline "${1:-${BOOT_LINUXLOADER_CFG_PATH}}"
}

# initrd = "initrd.img-6.18.8-edge-sm8550" in [Linux] → absolute path under /boot/
read_initrd_path_from_linuxloader_cfg() {
    local cfg="${1:-${BOOT_LINUXLOADER_CFG_PATH}}" rel boot="/boot"

    rel="$(read_linuxloader_linux_field initrd "${cfg}")" || return 1
    [[ -n "${rel}" ]] || return 1

    rel="${rel#\"}"; rel="${rel%\"}"
    if [[ "${rel}" == /* ]]; then
        echo "${rel}"
    else
        echo "${boot}/${rel}"
    fi
}

read_linuxloader_linux_field() {
    local field="$1" cfg="${2:-${BOOT_LINUXLOADER_CFG_PATH}}"
    [[ -f "${cfg}" ]] || return 1

    python3 - "${field}" "${cfg}" <<'PY'
import re, sys
from pathlib import Path

field, path = sys.argv[1], sys.argv[2]
text = Path(path).read_text(errors="replace")
section = text
m = re.search(r"\[Linux\](.*?)(?=\[|\Z)", text, re.DOTALL | re.IGNORECASE)
if m:
    section = m.group(1)
pat = rf'^\s*{re.escape(field)}\s*=\s*"(.*?)"\s*$|^\s*{re.escape(field)}\s*=\s*(\S.*?)\s*$'
m = re.search(pat, section, re.MULTILINE | re.IGNORECASE)
if m:
    print((m.group(1) or m.group(2) or "").strip())
PY
}

resolve_root_uuid() {
    local cmdline uuid
    local cfg="${BOOT_LINUXLOADER_CFG_PATH}"
    local kernel="${BOOT_KERNEL_PATH}"

    ROOT_UUID_SOURCE=""
    RESOLVED_ROOT_UUID=""

    # Explicit override (debug)
    if [[ -n "${ROOT_UUID:-}" ]]; then
        ROOT_UUID_SOURCE="ROOT_UUID override"
        RESOLVED_ROOT_UUID="${ROOT_UUID}"
        echo "${ROOT_UUID}"
        return 0
    fi

    if [[ -f "${cfg}" ]]; then
        cmdline="$(read_cmdline_from_linuxloader_cfg "${cfg}")" || true
        if [[ -n "${cmdline:-}" ]]; then
            uuid="$(extract_root_uuid_from_cmdline "${cmdline}")"
            if [[ -n "${uuid}" ]]; then
                ROOT_UUID_SOURCE="${cfg}"
                RESOLVED_ROOT_UUID="${uuid}"
                echo "${uuid}"
                return 0
            fi
            echo "Cmdline missing root=UUID= in ${cfg}:" >&2
            echo "  ${cmdline}" >&2
            return 1
        fi
        echo "Could not read cmdline from ${cfg}" >&2
        return 1
    fi

    [[ -f "${kernel}" ]] || {
        echo "Neither ${cfg} nor ${kernel} found — cannot read root=UUID=" >&2
        return 1
    }

    cmdline="$(read_cmdline_from_bootimg "${kernel}")" || {
        echo "Could not read cmdline from ${kernel}" >&2
        return 1
    }

    uuid="$(extract_root_uuid_from_cmdline "${cmdline}")"
    [[ -n "${uuid}" ]] || {
        echo "Cmdline missing root=UUID= in ${kernel}:" >&2
        echo "  ${cmdline}" >&2
        return 1
    }

    ROOT_UUID_SOURCE="${kernel}"
    RESOLVED_ROOT_UUID="${uuid}"
    echo "${uuid}"
}

build_abl_cmdline() {
    local uuid="${1:-}"
    [[ -n "${uuid}" ]] || {
        echo "Missing root UUID (read from ${BOOT_LINUXLOADER_CFG_PATH} or ${BOOT_KERNEL_PATH})" >&2
        return 1
    }

    # Match working LinuxLoader 6.18.8 baseline (no video=efifb:off — causes blue panel without HDMI).
    local -a parts=(
        "clk_ignore_unused"
        "pd_ignore_unused"
        "quiet"
        "rw"
        "rootwait"
        "root=UUID=${uuid}"
    )

    # Optional extras for legacy ABL — off by default (see docs/DISPLAY-BOOT.md).
    if [[ "${ABL_CMDLINE_EXTRAS:-0}" == "1" ]]; then
        parts+=("psi=0" "arm64.nopauth" "efi=noruntime" "video=efifb:off")
    fi

    if [[ -n "${KERNEL_CMDLINE_EXTRA:-}" ]]; then
        local extra
        read -ra extra <<<"${KERNEL_CMDLINE_EXTRA}"
        parts+=("${extra[@]}")
    fi

    local cmdline="${parts[*]}"
    if [[ "${cmdline}" == *"devicetree="* || "${cmdline}" == *"dtb="* ]]; then
        echo "cmdline must not include devicetree=/dtb= (ABL picks DTB)" >&2
        return 1
    fi
    printf '%s' "${cmdline}"
}
