#!/usr/bin/env bash
#
# lib/bootimg.sh — pack zImage (ABL+DTBs) + initrd → boot/KERNEL
# No devicetree= in cmdline — ABL picks the embedded DTB.
#
set -euo pipefail

copy_bootimg_hw_template() {
    local template="${1}" dest_cfg="$2"
    local work="${CACHE_DIR}/bootimg-template"

    [[ -f "${template}" ]] || {
        echo "Missing bootimg template: ${template}" >&2
        return 1
    }
    command -v abootimg >/dev/null 2>&1 || {
        echo "Install: sudo apt install abootimg" >&2
        return 1
    }

    rm -rf "${work}"
    mkdir -p "${work}"
    ( cd "${work}" && abootimg -x "${template}" >/dev/null 2>&1 )

    [[ -f "${work}/bootimg.cfg" ]] || {
        echo "Could not read bootimg.cfg from ${template}" >&2
        return 1
    }

    grep -E '^(bootsize|pagesize|kerneladdr|ramdiskaddr|secondaddr|tagsaddr|name) ' \
        "${work}/bootimg.cfg" > "${dest_cfg}"
    echo 'cmdline = PLACEHOLDER' >> "${dest_cfg}"
    echo "  bootimg template: $(basename "${template}")" >&2
    rm -rf "${work}"
}

resolve_bootimg_template() {
    local candidate
    if [[ -n "${BOOTIMG_TEMPLATE:-}" && -f "${BOOTIMG_TEMPLATE}" ]]; then
        echo "${BOOTIMG_TEMPLATE}"
        return 0
    fi
    if [[ -f /boot/KERNEL ]]; then
        echo "/boot/KERNEL"
        return 0
    fi
    for candidate in \
        "${ROOT}/device-tree/reference/KERNEL" \
        "${ROOT}/../Kernel-odin2/rocknix-boot-partition/KERNEL"; do
        [[ -f "${candidate}" ]] && readlink -f "${candidate}" && return 0
    done
    return 1
}

pack_bootimg_abl() {
    local out_dir="$1" release="${2:-}" uuid cmdline
    local staging
    staging="$(resolve_build_staging_dir "${out_dir}" "${release}")"
    local boot_dir="${out_dir}/boot"
    local zimage="${staging}/zImage"
    local initrd="${staging}/initrd.img-${release}"
    local cfg="${staging}/bootimg.cfg"
    local kernel_out="${boot_dir}/KERNEL"
    local template

    [[ -f "${zimage}" ]] || {
        echo "Missing ${zimage} — run dtb-chain first" >&2
        return 1
    }
    [[ -f "${initrd}" ]] || {
        echo "Missing ${initrd} — run initramfs first" >&2
        return 1
    }

    resolve_root_uuid || {
        echo "Could not get root=UUID= from ${BOOT_LINUXLOADER_CFG_PATH:-/boot/LinuxLoader.cfg} or ${BOOT_KERNEL_PATH:-/boot/KERNEL}" >&2
        return 1
    }
    uuid="${RESOLVED_ROOT_UUID}"
    echo "  root UUID: ${uuid} (from ${ROOT_UUID_SOURCE})" >&2

    cmdline="$(build_abl_cmdline "${uuid}")" || return 1

    template="$(resolve_bootimg_template)" || {
        echo "No bootimg template (BOOTIMG_TEMPLATE or ROCKNIX KERNEL)" >&2
        return 1
    }

    mkdir -p "${boot_dir}" "${staging}"
    copy_bootimg_hw_template "${template}" "${cfg}.hw"

    {
        grep -E '^(bootsize|pagesize|kerneladdr|ramdiskaddr|secondaddr|tagsaddr|name) ' \
            "${cfg}.hw"
        printf 'cmdline = %s\n' "${cmdline}"
    } > "${cfg}"
    rm -f "${cfg}.hw"

    echo "==> ABL bootimg: zImage + initrd → boot/KERNEL" >&2
    echo "  cmdline: ${cmdline}" >&2

    local ksize rsize max_boot need pagesize=4096
    ksize="$(stat -c%s "${zimage}")"
    rsize="$(stat -c%s "${initrd}")"
    max_boot="$(grep -E '^bootsize ' "${cfg}" | awk '{print $3}')"
    max_boot="${max_boot:-${BOOTIMG_MAX_BYTES:-82536448}}"
    need=$(( (ksize + pagesize - 1) / pagesize * pagesize + (rsize + pagesize - 1) / pagesize * pagesize + pagesize * 4 ))
    if [[ "${need}" -gt "${max_boot}" ]]; then
        echo "ERROR: bootimg too large (${need} vs bootsize ${max_boot} bytes)" >&2
        echo "  zImage: ${ksize} bytes | initrd: ${rsize} bytes" >&2
        echo "  initrd should be ~≤58 MB. Try INITRAMFS_PROFILE=gold" >&2
        return 1
    fi

    abootimg --create "${kernel_out}" -f "${cfg}" -k "${zimage}" -r "${initrd}" || {
        echo "ERROR: abootimg --create failed" >&2
        return 1
    }

    [[ -s "${kernel_out}" ]] || {
        echo "ERROR: ${kernel_out} empty after abootimg" >&2
        return 1
    }

    local ks rs
    abootimg -i "${kernel_out}" 2>&1 | grep -E 'kernel size|ramdisk size|cmdline' >&2 || true

    # Verify cmdline does not pin DTB via EFI
    assert_no_efi_devicetree "${cmdline}" || return 1

    write_output_install "${out_dir}" "${release}" "${uuid}"

    echo "  → ${kernel_out} ($(du -h "${kernel_out}" | cut -f1))" >&2
    export MASI_BOOT_KERNEL="${kernel_out}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    export ROOT
    : "${CACHE_DIR:=${ROOT}/.cache}"
    # shellcheck source=config/defaults.conf
    source "${ROOT}/config/defaults.conf"
    # shellcheck source=lib/cmdline.sh
    source "${ROOT}/lib/cmdline.sh"
    # shellcheck source=lib/dtb-chain/verify.sh
    source "${ROOT}/lib/dtb-chain/verify.sh"
    # shellcheck source=lib/output.sh
    source "${ROOT}/lib/output.sh"

    # shellcheck source=lib/output.sh
    source "${ROOT}/lib/output.sh"

    out="$(find "${OUTPUT_DIR:-${ROOT}/output}" -maxdepth 1 -type d -name '*-masi' 2>/dev/null | sort -V | tail -1)"
    [[ -n "${out}" ]] || { echo "No build output found"; exit 1; }
    rel="$(basename "$(find "${out}/modules" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)")"
    pack_bootimg_abl "${out}" "${rel}"
fi
