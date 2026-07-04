#!/usr/bin/env bash
# Discover SM8550 kernel series supported by Armbian patches.
set -euo pipefail

ARMBIAN_FAMILY_CONF="${ARMBIAN_PATCH_RAW}/config/sources/families/sm8550.conf"
ARMBIAN_ARCHIVE_API="https://api.github.com/repos/armbian/build/contents/patch/kernel/archive"
ARMBIAN_SUPPORT_CACHE="${CACHE_DIR}/armbian-support.env"
ARMBIAN_SUPPORT_TTL="${ARMBIAN_SUPPORT_TTL:-43200}"

declare -ga ARMBIAN_KERNEL_SERIES=()
declare -gA ARMBIAN_SERIES_PATCH_SET=()
declare -g ARMBIAN_EDGE_SERIES=""

FALLBACK_KERNEL_SERIES=(7 7.0 6.18)
declare -gA FALLBACK_SERIES_PATCH_SET=(
    ["7"]="sm8550-7"
    ["7.0"]="sm8550-7.0"
    ["6.18"]="sm8550-6.18"
)

_load_support_from_cache() {
    [[ -f "${ARMBIAN_SUPPORT_CACHE}" ]] || return 1
    # shellcheck source=/dev/null
    source "${ARMBIAN_SUPPORT_CACHE}"
    [[ ${#ARMBIAN_KERNEL_SERIES[@]} -gt 0 ]]
}

_save_support_cache() {
    {
        echo "# Armbian SM8550 — $(date -Iseconds)"
        echo "ARMBIAN_EDGE_SERIES=\"${ARMBIAN_EDGE_SERIES}\""
        echo -n "ARMBIAN_KERNEL_SERIES=("
        printf '%s ' "${ARMBIAN_KERNEL_SERIES[@]}"
        echo ")"
        local s
        for s in "${ARMBIAN_KERNEL_SERIES[@]}"; do
            echo "ARMBIAN_SERIES_PATCH_SET_${s//./_}=\"${ARMBIAN_SERIES_PATCH_SET[$s]}\""
        done
    } > "${ARMBIAN_SUPPORT_CACHE}.tmp"
    mv "${ARMBIAN_SUPPORT_CACHE}.tmp" "${ARMBIAN_SUPPORT_CACHE}"
}

_fetch_patch_sets_from_github() {
    curl -fsSL --connect-timeout 15 --max-time 45 "${ARMBIAN_ARCHIVE_API}" \
        | python3 -c "
import sys, json, re
for item in sorted(json.load(sys.stdin), key=lambda x: x['name']):
    m = re.match(r'^sm8550-(\d+(?:\.\d+)?)\$', item['name'])
    if m:
        print(f\"{m.group(1)} {item['name']}\")
"
}

_rebuild_patch_set_map_from_cache_vars() {
    ARMBIAN_SERIES_PATCH_SET=()
    local s key
    for s in "${ARMBIAN_KERNEL_SERIES[@]}"; do
        key="ARMBIAN_SERIES_PATCH_SET_${s//./_}"
        ARMBIAN_SERIES_PATCH_SET["${s}"]="${!key:-sm8550-${s}}"
    done
}

_use_fallback_support() {
    ARMBIAN_KERNEL_SERIES=("${FALLBACK_KERNEL_SERIES[@]}")
    ARMBIAN_SERIES_PATCH_SET=()
    local s
    for s in "${FALLBACK_KERNEL_SERIES[@]}"; do
        ARMBIAN_SERIES_PATCH_SET["${s}"]="${FALLBACK_SERIES_PATCH_SET[$s]}"
    done
    ARMBIAN_EDGE_SERIES="${FALLBACK_KERNEL_SERIES[0]}"
    echo "  fallback: ${ARMBIAN_KERNEL_SERIES[*]}" >&2
}

refresh_armbian_support() {
    local cache_age=999999
    if [[ -f "${ARMBIAN_SUPPORT_CACHE}" ]]; then
        cache_age=$(( $(date +%s) - $(stat -c %Y "${ARMBIAN_SUPPORT_CACHE}" 2>/dev/null || echo 0) ))
    fi

    if [[ "${cache_age}" -lt "${ARMBIAN_SUPPORT_TTL}" ]] && _load_support_from_cache; then
        _rebuild_patch_set_map_from_cache_vars
        return 0
    fi

    echo "==> Querying Armbian SM8550 patches..." >&2
    local -a series=() patch_sets=() line mm ps

    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        mm="${line%% *}"
        ps="${line#* }"
        series+=("${mm}")
        patch_sets+=("${ps}")
    done < <(_fetch_patch_sets_from_github) || {
        echo "WARNING: GitHub Armbian inaccesible." >&2
        _load_support_from_cache && return 0
        _use_fallback_support
        return 0
    }

    if [[ ${#series[@]} -eq 0 ]]; then
        _load_support_from_cache && return 0
        _use_fallback_support
        return 0
    fi

    ARMBIAN_KERNEL_SERIES=()
    ARMBIAN_SERIES_PATCH_SET=()
    local i
    for i in "${!series[@]}"; do
        ARMBIAN_SERIES_PATCH_SET["${series[$i]}"]="${patch_sets[$i]}"
    done
    readarray -t ARMBIAN_KERNEL_SERIES < <(printf '%s\n' "${series[@]}" | sort -Vr)
    ARMBIAN_EDGE_SERIES="${ARMBIAN_KERNEL_SERIES[0]}"
    _save_support_cache
    echo "  series: ${ARMBIAN_KERNEL_SERIES[*]}" >&2
}

_patch_set_keys_for_version() {
    local ver="$1"
    local mm="${ver%.*}"
    local maj="${ver%%.*}"
    if [[ "${mm}" == "${maj}" ]]; then
        echo "${mm}"
    else
        printf '%s\n%s\n' "${mm}" "${maj}"
    fi
}

patch_set_for_version() {
    local ver="$1" key ps
    while IFS= read -r key; do
        [[ -n "${key}" ]] || continue
        ps="${ARMBIAN_SERIES_PATCH_SET[$key]:-}"
        if [[ -n "${ps}" ]]; then
            echo "${ps}"
            return 0
        fi
    done < <(_patch_set_keys_for_version "${ver}")
    echo "No Armbian patches for linux-${ver}." >&2
    return 1
}

kernel_is_supported() {
    patch_set_for_version "$1" >/dev/null 2>&1
}

armbian_support_summary() {
    local s parts=()
    for s in "${ARMBIAN_KERNEL_SERIES[@]}"; do
        if [[ "${s}" == *.* ]]; then
            parts+=("${s}.x (${ARMBIAN_SERIES_PATCH_SET[$s]:-?})")
        else
            parts+=("${s}.x+ (${ARMBIAN_SERIES_PATCH_SET[$s]:-?})")
        fi
    done
    local IFS=', '
    echo "${parts[*]}"
}

_try_kernel_version() {
    local ver="$1"
    kernel_is_supported "${ver}" || return 1
    kernel_source_cached "${ver}" && return 0
    kernel_tarball_exists "${ver}"
}

# Interactive menu versions (no per-tarball CDN HEAD).
enumerate_kernel_menu_versions() {
    local -a versions=()
    local series ver max per n

    refresh_armbian_support
    max="${KERNEL_VERSIONS_PER_SERIES:-8}"
    per=$(( max * ${#ARMBIAN_KERNEL_SERIES[@]} + 4 ))

    for series in "${ARMBIAN_KERNEL_SERIES[@]}"; do
        echo "  → ${series}.x (${ARMBIAN_SERIES_PATCH_SET[$series]:-?}) ..." >&2
        n=0
        while IFS= read -r ver; do
            [[ -n "${ver}" ]] || continue
            kernel_is_supported "${ver}" || continue
            versions+=("${ver}")
            n=$((n + 1))
            [[ "${n}" -ge "${max}" ]] && break
        done < <(kernel_list_versions_for_series "${series}")
    done

    ver="$(uname -r 2>/dev/null | cut -d- -f1 || true)"
    if [[ -n "${ver}" ]] && kernel_is_supported "${ver}"; then
        versions+=("${ver}")
    fi

    if [[ ${#versions[@]} -eq 0 ]]; then
        for ver in ${FALLBACK_KERNEL_VERSIONS:-}; do
            [[ -n "${ver}" ]] || continue
            kernel_is_supported "${ver}" || continue
            versions+=("${ver}")
        done
    fi

    [[ ${#versions[@]} -gt 0 ]] || return 1

    # sort -rV (not tac — tac uses /tmp and fails when tmpfs is full)
    while IFS= read -r ver; do
        [[ -n "${ver}" ]] && echo "${ver}"
    done < <(printf '%s\n' "${versions[@]}" | sort -rVu | head -n "${per}")
}

# Auto / no interactivo: preferir cache o tarball verificado.
enumerate_downloadable_kernels() {
    local ver
    while IFS= read -r ver; do
        [[ -n "${ver}" ]] || continue
        _try_kernel_version "${ver}" && echo "${ver}"
    done < <(enumerate_kernel_menu_versions) || return 1
}

resolve_kernel_version() {
    if [[ -n "${KERNEL_VER:-}" ]]; then
        kernel_is_supported "${KERNEL_VER}" || {
            echo "KERNEL_VER=${KERNEL_VER} not supported." >&2
            return 1
        }
        echo "${KERNEL_VER}"
        return 0
    fi

    local ver
    ver="$(enumerate_downloadable_kernels 2>/dev/null | head -1)" && {
        echo "  auto: linux-${ver}" >&2
        echo "${ver}"
        return 0
    }

    ver="$(enumerate_kernel_menu_versions 2>/dev/null | head -1)" || {
        echo "No compatible versions. Try KERNEL_VER=7.0.14 ./make.sh" >&2
        return 1
    }
    echo "  auto: linux-${ver} (download without CDN verify)" >&2
    echo "${ver}"
}
