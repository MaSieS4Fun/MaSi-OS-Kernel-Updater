#!/usr/bin/env bash
set -euo pipefail

_patch_is_skipped() {
    local base="$1" deny_list="${2:-${PATCH_SKIP:-}}" deny pat
    [[ -z "${deny_list}" ]] && return 1
    IFS=',' read -ra deny <<< "${deny_list}"
    for pat in "${deny[@]}"; do
        pat="${pat// /}"
        [[ -z "${pat}" ]] && continue
        [[ "${base}" == *"${pat}"* ]] && return 0
    done
    return 1
}

apply_armbian_patches() {
    local src_dir="$1" patch_set="$2" kernel_ver="$3"
    local patch_dir failed=0 applied=0 skipped=0 denied=0
    local stamp="${src_dir}/.masi-patched-${patch_set}-ok"
    patch_dir="$(fetch_armbian_patches "${patch_set}")"
    mkdir -p "${OUTPUT_DIR}"
    local log="${OUTPUT_DIR}/patch-log-${patch_set}.txt"
    : > "${log}"

    if [[ -f "${stamp}" ]]; then
        echo "==> Patches ${patch_set} already applied (linux-${kernel_ver})" >&2
        return 0
    fi

    reset_kernel_source_from_tarball "${kernel_ver}" || return 1

    echo "==> Applying patches ${patch_set} (linux-${kernel_ver})" >&2
    shopt -s nullglob
    local patch base fail_log
    for patch in "${patch_dir}"/*.patch; do
        base="$(basename "${patch}")"
        if _patch_is_skipped "${base}" "${PATCH_SKIP:-}"; then
            echo "  DENY ${base}" >&2
            denied=$((denied + 1))
            continue
        fi
        if patch -p1 --dry-run -d "${src_dir}" -f < "${patch}" >/dev/null 2>&1; then
            patch -p1 -d "${src_dir}" -f < "${patch}" >> "${log}" 2>&1 && {
                echo "  OK   ${base}" >&2
                applied=$((applied + 1))
            } || { echo "  FAIL ${base}" >&2; failed=$((failed + 1)); }
        elif patch -p1 --dry-run -R -d "${src_dir}" -f < "${patch}" >/dev/null 2>&1; then
            echo "  SKIP ${base}" >&2
            skipped=$((skipped + 1))
        else
            echo "  FAIL ${base}" >&2
            fail_log="${OUTPUT_DIR}/patch-fail-${base}.txt"
            patch -p1 --dry-run -d "${src_dir}" -f < "${patch}" > "${fail_log}" 2>&1 || true
            failed=$((failed + 1))
        fi
    done
    shopt -u nullglob

    echo "==> Patches: ${applied} ok, ${skipped} skip, ${denied} deny, ${failed} fail" >&2
    if [[ "${failed}" -gt 0 ]]; then
        echo "BUILD ABORTED — see ${log} and patch-fail-*.txt in ${OUTPUT_DIR}/" >&2
        echo "  Tip: rm -rf ${src_dir} if the source tree is inconsistent." >&2
        [[ "${PATCH_POLICY}" == "tolerant" ]] && return 0
        return 1
    fi

    touch "${stamp}"
}

warn_config_source() {
    local base="$1"
    echo "==> Config: ${base}" >&2
    case "${base}" in
        *"/config/golden.config") echo "  MaSi-OS gaming profile" >&2 ;;
        *linux-sm8550-edge.config) echo "  WARNING: fallback defconfig Armbian" >&2 ;;
    esac
}

apply_gaming_kconfig_overrides() {
    local src_dir="$1" cfg="${src_dir}/.config" sc="${src_dir}/scripts/config"
    [[ -f "${cfg}" && -x "${sc}" ]] || return 0

    echo "==> Overrides gaming kconfig" >&2
    "${sc}" --file "${cfg}" \
        --enable SCHED_SMT --enable SCHED_MC --enable SCHED_CLUSTER \
        --disable PSI \
        --enable MMC_SDHCI_MSM_DOWNSTREAM \
        --set-str CPU_FREQ_DEFAULT_GOV_PERFORMANCE \
        --disable CPU_FREQ_DEFAULT_GOV_SCHEDUTIL \
        --enable CPU_FREQ_GOV_PERFORMANCE \
        --enable ENERGY_MODEL \
        --enable CC_OPTIMIZE_FOR_PERFORMANCE \
        --disable CC_OPTIMIZE_FOR_SIZE 2>/dev/null || true

    "${sc}" --file "${cfg}" --module DRM_LONTIUM_LT8912B 2>/dev/null || \
        "${sc}" --file "${cfg}" --disable DRM_LONTIUM_LT8912B 2>/dev/null || true

    make -C "${src_dir}" ARCH=arm64 olddefconfig
}

apply_ayn_family_kconfig() {
    local src_dir="$1" cfg="${src_dir}/.config" sc="${src_dir}/scripts/config" sym
    [[ -f "${cfg}" && -x "${sc}" ]] || return 0
    [[ "${AYN_FAMILY_DRIVERS:-1}" == "0" ]] && return 0

    echo "==> AYN SM8550 family drivers" >&2
    for sym in \
        DRM_PANEL_SYNAPTICS_TD4328 DRM_PANEL_BOE_XM91080G \
        DRM_PANEL_CHIPONE_ICNA3512 DRM_PANEL_CHIPONE_ICNA35XX \
        DRM_PANEL_DDIC_CH13726A \
        TOUCHSCREEN_HYNITRON_CSTXXX TOUCHSCREEN_HYNITRON_ALL \
        TOUCHSCREEN_FOCALTECH_FT5426 TOUCHSCREEN_FOCALTECH_FT5X06 \
        TOUCHSCREEN_EDT_FT5X06 \
        BACKLIGHT_ODIN2MINI BACKLIGHT_SY7758
    do
        "${sc}" --file "${cfg}" --enable "${sym}" 2>/dev/null || true
    done
    make -C "${src_dir}" ARCH=arm64 olddefconfig
}

apply_gaming_config_tweaks() {
    local src_dir="$1"
    [[ "${GAMING_TUNING:-1}" == "0" ]] && return 0
    apply_gaming_kconfig_overrides "${src_dir}"
    apply_ayn_family_kconfig "${src_dir}"
}

prepare_kernel_config() {
    local src_dir="$1" kernel_ver="$2" base
    base="$(resolve_kernel_config "${kernel_ver}")"
    [[ -f "${base}" ]] || base="$(fetch_armbian_defconfig)"

    warn_config_source "${base}"
    cp "${base}" "${src_dir}/.config"
    make -C "${src_dir}" ARCH=arm64 olddefconfig
    "${src_dir}/scripts/config" --file "${src_dir}/.config" \
        --set-str LOCALVERSION "${KERNEL_LOCALVERSION}"
    make -C "${src_dir}" ARCH=arm64 olddefconfig
    apply_gaming_config_tweaks "${src_dir}"
}
