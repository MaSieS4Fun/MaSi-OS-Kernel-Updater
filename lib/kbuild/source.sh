#!/usr/bin/env bash
set -euo pipefail

download_kernel_source() {
    local ver="$1" dest tar src_dir url ok=0
    dest="${CACHE_DIR}/linux-${ver}"
    src_dir="${dest}"

    if [[ -f "${src_dir}/Makefile" ]]; then
        local mkver
        mkver="$(make -s -C "${src_dir}" kernelversion 2>/dev/null || true)"
        if [[ "${mkver}" == "${ver}" ]]; then
            echo "${src_dir}"
            return 0
        fi
    fi

    echo "==> Downloading linux-${ver}" >&2
    while IFS= read -r url; do
        [[ -n "${url}" ]] || continue
        tar="$(kernel_tarball_archive_path "${ver}" "${url}")"
        if [[ -f "${tar}" ]]; then
            if kernel_tarball_validate "${tar}"; then
                ok=1
                break
            fi
            echo "  invalid cache (${tar}), re-downloading ..." >&2
            rm -f "${tar}"
        fi
        echo "  trying ${url} ..." >&2
        if curl -fsSL --connect-timeout 15 --max-time 600 -A "${KERNEL_CDN_UA}" -L -o "${tar}.partial" "${url}" \
            && kernel_tarball_validate "${tar}.partial"; then
            mv "${tar}.partial" "${tar}"
            ok=1
            break
        fi
        rm -f "${tar}.partial"
    done < <(kernel_tarball_urls "${ver}")

    if [[ "${ok}" != "1" ]]; then
        echo "Error: could not download linux-${ver} (CDN + GitHub gregkh/linux)" >&2
        echo "  Pick another version in the menu or check network/proxy." >&2
        return 1
    fi

    echo "==> Extracting linux-${ver}" >&2
    src_dir="$(extract_kernel_tarball "${tar}" "${CACHE_DIR}" "${ver}")" || return 1
    echo "${src_dir}"
}

fetch_armbian_defconfig() {
    local dest="${CACHE_DIR}/linux-sm8550-edge.config"
    if [[ ! -f "${dest}" ]]; then
        echo "==> Downloading Armbian sm8550 defconfig" >&2
        curl -fsSL --max-time 30 \
            "${ARMBIAN_PATCH_RAW}/config/kernel/linux-sm8550-edge.config" \
            -o "${dest}"
    fi
    echo "${dest}"
}

fetch_armbian_patches() {
    local patch_set="$1" dest="${PATCH_CACHE}/${patch_set}"
    local api="https://api.github.com/repos/armbian/build/contents/patch/kernel/archive/${patch_set}"

    if [[ -d "${dest}" && -n "$(ls -A "${dest}"/*.patch 2>/dev/null)" ]]; then
        echo "${dest}"
        return 0
    fi

    echo "==> Downloading patches ${patch_set}" >&2
    mkdir -p "${dest}"

    local names name
    names="$(curl -fsSL --max-time 60 "${api}" | python3 -c "
import sys, json
for item in sorted(json.load(sys.stdin), key=lambda x: x['name']):
    if item['name'].endswith('.patch'):
        print(item['name'])
")"

    for name in ${names}; do
        curl -fsSL --max-time 60 \
            "${ARMBIAN_PATCH_RAW}/patch/kernel/archive/${patch_set}/${name}" \
            -o "${dest}/${name}"
    done
    echo "${dest}"
}
