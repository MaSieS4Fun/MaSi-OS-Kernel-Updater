#!/usr/bin/env bash
set -euo pipefail

# Clean install bundle: boot/, firmware/, modules/, INSTALL.txt
build_artifact_dir() {
    local release="$1"
    echo "${OUTPUT_DIR}/${release}-${OUTPUT_SUFFIX:-masi}"
}

# Intermediate build tree (Image, zImage, initrd, DTB chain) — not for install.
build_staging_dir() {
    local release="$1"
    echo "${OUTPUT_DIR}/.build/${release}-${OUTPUT_SUFFIX:-masi}"
}

build_staging_dir_for() {
    local artifact_dir="$1"
    echo "${OUTPUT_DIR}/.build/$(basename "${artifact_dir}")"
}

resolve_build_staging_dir() {
    local artifact_dir="$1" release="${2:-}" staging

    if [[ -n "${release}" ]]; then
        staging="$(build_staging_dir "${release}")"
    else
        staging="$(build_staging_dir_for "${artifact_dir}")"
    fi

    if [[ -f "${staging}/Image" ]]; then
        echo "${staging}"
        return 0
    fi

    # Legacy: staging lived inside the artifact dir
    if [[ -f "${artifact_dir}/.staging/Image" ]]; then
        echo "${artifact_dir}/.staging"
        return 0
    fi

    echo "${staging}"
}

build_meta_dir() {
    echo "${OUTPUT_DIR}/meta"
}

write_output_install() {
    local out_dir="$1" release="${2:-}" uuid="${3:-}"
    local meta_cfg="meta/config-${release} (under ${OUTPUT_DIR}/)"

    cat > "${out_dir}/INSTALL.txt" <<EOF
Kernel_MaSi-OS — installation
=============================
release: ${release}
root UUID: ${uuid} (from ${ROOT_UUID_SOURCE:-${BOOT_LINUXLOADER_CFG_PATH:-/boot/LinuxLoader.cfg} or ${BOOT_KERNEL_PATH:-/boot/KERNEL}})

Output layout (this folder)
  boot/KERNEL          →  /boot/KERNEL
  boot/KERNEL.md5      →  bootimg checksum (verification)
  firmware/            →  /usr/lib/firmware/
  modules/${release}/  →  /usr/lib/modules/${release}/

Build artifacts (not installed)
  ${OUTPUT_DIR}/.build/${release}-${OUTPUT_SUFFIX:-masi}/  — Image, zImage, initrd
  ${OUTPUT_DIR}/${meta_cfg}  — kernel .config reference

Automatic install:
  sudo ./update.sh

Manual install:
  sudo cp boot/KERNEL /boot/KERNEL
  sudo cp -a firmware/. /usr/lib/firmware/
  sudo cp -a modules/${release} /usr/lib/modules/
  sudo reboot

DTB: picked by ABL (chain in zImage) — do NOT use devicetree= in GRUB.
After boot:
  tr -d '\\0' < /proc/device-tree/model
EOF

    cat > "${out_dir}/MANIFEST.txt" <<EOF
Kernel_MaSi-OS build
date: $(date -Iseconds)
release: ${release}
root_uuid: ${uuid}
boot: boot/KERNEL
firmware: firmware/
modules: modules/${release}/
staging: .build/${release}-${OUTPUT_SUFFIX:-masi}/
config_reference: meta/config-${release}
gaming_tuning: ${GAMING_TUNING:-1}
initramfs_profile: ${INITRAMFS_PROFILE:-gold}
EOF
}

finalize_output_layout() {
    local out_dir="$1" release="${2:-}"
    local kernel="${out_dir}/boot/KERNEL"
    local staging meta_cfg staging_cfg

    mkdir -p "${out_dir}/boot" "${out_dir}/firmware" "${out_dir}/modules"
    staging="$(resolve_build_staging_dir "${out_dir}" "${release}")"
    meta_cfg="$(build_meta_dir)/config-${release}"

    if [[ -f "${kernel}" ]]; then
        md5sum "${kernel}" | awk '{print $1}' > "${out_dir}/boot/KERNEL.md5"
        echo "  boot/KERNEL.md5 ($(cut -c1-8 < "${out_dir}/boot/KERNEL.md5"))" >&2
    fi

    find "${out_dir}/modules" -mindepth 2 -maxdepth 2 \( -name source -o -name build \) -type l -delete 2>/dev/null || true

    staging_cfg="${staging}/config-${release}"
    if [[ -f "${staging_cfg}" ]]; then
        mkdir -p "$(build_meta_dir)"
        cp -f "${staging_cfg}" "${meta_cfg}" 2>/dev/null || true
        echo "  meta/config-${release}" >&2
    fi

    # Keep artifact dir clean — no .staging/ or meta/ here
    rm -rf "${out_dir}/.staging" "${out_dir}/meta" "${out_dir}/.modules-staging" 2>/dev/null || true

    echo "==> Output ready:" >&2
    echo "  ${out_dir}/boot/KERNEL" >&2
    echo "  ${out_dir}/boot/KERNEL.md5" >&2
    echo "  ${out_dir}/firmware/" >&2
    echo "  ${out_dir}/modules/${release}/" >&2
    echo "  (build tree: ${staging}/)" >&2
}
