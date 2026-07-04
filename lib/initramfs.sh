#!/usr/bin/env bash
#
# lib/initramfs.sh — initrd for ABL bootimg (gold ref or minimal mkinitramfs)
#
set -euo pipefail

_initrd_try_ref() {
    local candidate="$1"
    [[ -n "${candidate}" && -f "${candidate}" ]] || return 1
    echo "${candidate}"
    return 0
}

# Cache /boot initrd into reference/ for reproducible gold builds.
_initrd_cache_reference() {
    local src="$1"
    local dest_dir="${ROOT}/reference"
    local base dest

    [[ -f "${src}" ]] || return 1
    [[ "${src}" == "${ROOT}/reference/"* ]] && {
        echo "${src}"
        return 0
    }

    mkdir -p "${dest_dir}"
    base="$(basename "${src}")"
    dest="${dest_dir}/${base}"
    cp -f "${src}" "${dest}" 2>/dev/null || return 1
    echo "${dest}"
}

# Prefer reference/ copy; fall back to the source path if cache is not writable.
_initrd_use_or_cache() {
    local src="$1" cached

    [[ -f "${src}" ]] || return 1
    [[ "${src}" == "${ROOT}/reference/"* ]] && {
        echo "${src}"
        return 0
    }

    if cached="$(_initrd_cache_reference "${src}")"; then
        echo "  gold: cached $(basename "${src}") → reference/" >&2
        echo "${cached}"
        return 0
    fi

    echo "  gold: using ${src} (reference/ cache unavailable)" >&2
    echo "${src}"
}

# Extract initrd from an ABL bootimg (e.g. /boot/KERNEL).
_extract_initrd_from_bootimg() {
    local kernel="$1" work="${CACHE_DIR:-/tmp}/initrd-from-bootimg-$$"

    [[ -f "${kernel}" ]] || return 1
    command -v abootimg >/dev/null 2>&1 || return 1

    rm -rf "${work}"
    mkdir -p "${work}"
    if ! ( cd "${work}" && abootimg -x "${kernel}" >/dev/null 2>&1 ); then
        rm -rf "${work}"
        return 1
    fi
    [[ -f "${work}/initrd.img" ]] || {
        rm -rf "${work}"
        return 1
    }

    local extracted="${CACHE_DIR:-/tmp}/initrd-from-bootimg-$$.img"
    cp -f "${work}/initrd.img" "${extracted}"
    rm -rf "${work}"
    _initrd_use_or_cache "${extracted}"
}

resolve_gold_initrd_ref() {
    local ver="${1:-}" candidate cfg_initrd bootimg

    for candidate in \
        "${GOLD_INITRD_REF:-}" \
        "${ROOT}/reference/initrd.img-${ver}" \
        "${ROOT}/device-tree/reference/initrd.img-${ver}" \
        "/boot/initrd.img-${ver}"; do
        _initrd_try_ref "${candidate}" && return 0
    done

    if cfg_initrd="$(read_initrd_path_from_linuxloader_cfg 2>/dev/null || true)"; then
        if [[ -n "${cfg_initrd}" && -f "${cfg_initrd}" ]]; then
            echo "  gold: initrd from ${BOOT_LINUXLOADER_CFG_PATH:-/boot/LinuxLoader.cfg}" >&2
            _initrd_use_or_cache "${cfg_initrd}"
            return 0
        fi
    fi

    shopt -s nullglob
    for candidate in "${ROOT}/reference"/initrd.img-*; do
        _initrd_try_ref "${candidate}" && {
            echo "  gold: using ${candidate} (no exact initrd.img-${ver})" >&2
            shopt -u nullglob
            return 0
        }
    done

    for candidate in \
        "/boot/initrd.img-${ver}" \
        /boot/initrd.img-*edge-sm8550* \
        /boot/initrd.img-*; do
        [[ -f "${candidate}" ]] || continue
        shopt -u nullglob
        _initrd_use_or_cache "${candidate}"
        return 0
    done
    shopt -u nullglob

    for bootimg in \
        "${BOOT_KERNEL_PATH:-/boot/KERNEL}" \
        /boot/KERNEL; do
        [[ -f "${bootimg}" ]] || continue
        if candidate="$(_extract_initrd_from_bootimg "${bootimg}")"; then
            echo "  gold: initrd extracted from ${bootimg}" >&2
            echo "${candidate}"
            return 0
        fi
    done

    return 1
}

build_initramfs_gold() {
    local out_dir="$1" release="$2"
    local staging ref size

    staging="$(resolve_build_staging_dir "${out_dir}" "${release}")"
    local initrd="${staging}/initrd.img-${release}"

    ref="$(resolve_gold_initrd_ref "${release}")" || {
        echo "initramfs gold: no reference initrd found." >&2
        echo "  Run: ./scripts/setup-reference-initrd.sh" >&2
        echo "  Or:  GOLD_INITRD_REF=/path/to/initrd.img ./make.sh" >&2
        return 1
    }

    mkdir -p "${staging}"
    cp -f "${ref}" "${initrd}"
    size="$(du -h "${initrd}" | cut -f1)"
    echo "  initrd gold: $(basename "${ref}") → initrd.img-${release} (${size})" >&2
    export MASI_INITRD="${initrd}"
}

_install_initramfs_hooks() {
    local mod_root="$1" profile="$2" fw_mode="$3" out_dir="$4"

    mkdir -p "${mod_root}/etc/initramfs-tools/hooks" \
        "${mod_root}/etc/initramfs-tools/conf.d"

    install -m755 "${ROOT}/hooks/masi-no-early-drm" \
        "${mod_root}/etc/initramfs-tools/hooks/masi-no-early-drm"

    case "${profile}" in
        efi-clean|minimal)
            cat > "${mod_root}/etc/initramfs-tools/initramfs.conf" <<'EOF'
MODULES=list
BUSYBOX=y
KEYFILE=n
COMPRESS=gzip
UMASK=0077
EOF
            : > "${mod_root}/etc/initramfs-tools/modules"
            install -m644 "${ROOT}/hooks/masi-efi-clean.conf" \
                "${mod_root}/etc/initramfs-tools/conf.d/masi-efi-clean.conf"
            install -m755 "${ROOT}/hooks/zz-masi-strip-initrd-bloat" \
                "${mod_root}/etc/initramfs-tools/hooks/zz-masi-strip-initrd-bloat"
            echo "  initramfs: ${profile} (MODULES=list, no firmware/modules in cpio)" >&2
            ;;
        full)
            echo 'MODULES=most' > "${mod_root}/etc/initramfs-tools/conf.d/masi-full.conf"
            echo "  initramfs: full (MODULES=most)" >&2
            ;;
        *)
            echo "Unknown initramfs profile: ${profile}" >&2
            return 1
            ;;
    esac

    if [[ "${fw_mode}" != "none" ]]; then
        install -m755 "${ROOT}/hooks/masi-firmware" \
            "${mod_root}/etc/initramfs-tools/hooks/masi-firmware"
        case "${fw_mode}" in
            staging)
                if [[ -d "${out_dir}/firmware" ]]; then
                    echo "${out_dir}/firmware" > "${mod_root}/etc/masi-firmware-staging"
                    echo "  firmware initrd: staging (minimal hook paths)" >&2
                fi
                ;;
            host|minimal)
                echo "  firmware initrd: minimal paths from host /lib/firmware" >&2
                ;;
        esac
    else
        echo "  firmware initrd: none (use rootfs /usr/lib/firmware)" >&2
    fi
}

_seed_modules_for_mkinitramfs() {
    local mod_root="$1" modules_src="$2" release="$3"

    [[ -d "${modules_src}" ]] || return 0

    mkdir -p "${mod_root}/lib/modules"
    rm -rf "${mod_root}/lib/modules/${release}"
    cp -a "${modules_src}" "${mod_root}/lib/modules/${release}"
    depmod -b "${mod_root}" "${release}" 2>/dev/null || true
}

build_initramfs_masi() {
    local out_dir="$1" release="${2:-}"
    local staging mod_root initrd profile fw_mode
    local mkinitramfs_cmd="/usr/sbin/mkinitramfs"
    local modules_src="${out_dir}/modules/${release}"
    local gold_fallback=0

    staging="$(resolve_build_staging_dir "${out_dir}" "${release}")"
    mod_root="${staging}/.initramfs-root"
    profile="${INITRAMFS_PROFILE:-gold}"
    fw_mode="${FIRMWARE_IN_INITRD:-minimal}"

    [[ -n "${release}" ]] || {
        echo "initramfs: missing release" >&2
        return 1
    }

    case "${profile}" in
        gold|gold-ref)
            if build_initramfs_gold "${out_dir}" "${release}"; then
                return 0
            fi
            echo "  gold unavailable — falling back to efi-clean (no firmware in initrd)" >&2
            profile="efi-clean"
            fw_mode="none"
            gold_fallback=1
            ;;
    esac

    command -v mkinitramfs >/dev/null 2>&1 || [[ -x "${mkinitramfs_cmd}" ]] || {
        echo "Install: sudo apt install initramfs-tools" >&2
        return 1
    }

    initrd="${staging}/initrd.img-${release}"
    mkdir -p "${staging}"
    rm -rf "${mod_root}"
    mkdir -p "${mod_root}"

    _install_initramfs_hooks "${mod_root}" "${profile}" "${fw_mode}" "${out_dir}" || return 1

    if [[ "${profile}" == "full" ]]; then
        [[ -d "${modules_src}" ]] || {
            echo "initramfs full: missing ${modules_src}" >&2
            return 1
        }
    fi

    _seed_modules_for_mkinitramfs "${mod_root}" "${modules_src}" "${release}"

    echo "==> mkinitramfs ${release}..." >&2
    if [[ "${gold_fallback}" -eq 1 ]]; then
        echo "  (warnings about UUID fsck or /etc/shadow are usually harmless)" >&2
    fi

    if command -v mkinitramfs >/dev/null 2>&1; then
        mkinitramfs -k "${release}" -r "${mod_root}" -o "${initrd}" 2>&1 | tail -12 >&2
    else
        "${mkinitramfs_cmd}" -k "${release}" -r "${mod_root}" -o "${initrd}" 2>&1 | tail -12 >&2
    fi

    [[ -f "${initrd}" ]] || {
        echo "initramfs failed: ${initrd} was not created" >&2
        return 1
    }

    rm -rf "${mod_root}"
    local size ko max_mb="${INITRD_MAX_MB:-62}"
    size="$(du -h "${initrd}" | cut -f1)"
    ko="$(lsinitramfs "${initrd}" 2>/dev/null | grep -c '\.ko$' || echo 0)"
    echo "  initrd.img-${release} (${size}, ${ko} .ko in cpio)" >&2

    if [[ "$(stat -c%s "${initrd}")" -gt $((max_mb * 1024 * 1024)) ]]; then
        echo "ERROR: initrd > ${max_mb} MB — does not fit ABL bootimg (~78 MB total)." >&2
        echo "  Fix: ./scripts/setup-reference-initrd.sh   then INITRAMFS_PROFILE=gold ./make.sh" >&2
        echo "  Or:  FIRMWARE_IN_INITRD=none INITRAMFS_PROFILE=efi-clean ./make.sh" >&2
        return 1
    fi

    export MASI_INITRD="${initrd}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    export ROOT
    # shellcheck source=config/defaults.conf
    source "${ROOT}/config/defaults.conf"
    # shellcheck source=lib/cmdline.sh
    source "${ROOT}/lib/cmdline.sh"
    # shellcheck source=lib/output.sh
    source "${ROOT}/lib/output.sh"
    out="$(find "${OUTPUT_DIR:-${ROOT}/output}" -maxdepth 1 -type d -name '*-masi' 2>/dev/null | sort -V | tail -1)"
    [[ -n "${out}" ]] || { echo "No build output found"; exit 1; }
    rel="$(basename "$(find "${out}/modules" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)")"
    build_initramfs_masi "${out}" "${rel}"
fi
