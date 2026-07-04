#!/usr/bin/env bash
# Assemble slot-00..slot-10 per config/dtb-chain.map
set -euo pipefail

assemble_dtb_chain() {
    local out_dir="$1" kbuild_dtb_dir="${2:-}" ref_dir="${3:-}"
    local map="${ROOT}/config/dtb-chain.map"
    local slot source kbuild_dtb device src_path

    [[ -f "${map}" ]] || {
        echo "Missing ${map}" >&2
        return 1
    }
    [[ -d "${ref_dir}" ]] || {
        echo "Missing DTB reference directory: ${ref_dir}" >&2
        return 1
    }

    rm -rf "${out_dir}"
    mkdir -p "${out_dir}"

    echo "==> Assembling ABL DTB chain (11 slots)..." >&2

    while IFS='|' read -r slot source kbuild_dtb device; do
        [[ -z "${slot}" || "${slot}" =~ ^# ]] && continue
        slot="$(printf '%02d' "${slot}")"
        src_path=""

        case "${source}" in
            reference)
                src_path="${ref_dir}/slot-${slot}.dtb"
                ;;
            kbuild)
                if [[ -n "${kbuild_dtb}" && -f "${kbuild_dtb_dir}/${kbuild_dtb}" ]]; then
                    src_path="${kbuild_dtb_dir}/${kbuild_dtb}"
                    echo "  slot-${slot}: kbuild ${kbuild_dtb} (${device})" >&2
                elif [[ -f "${ref_dir}/slot-${slot}.dtb" ]]; then
                    src_path="${ref_dir}/slot-${slot}.dtb"
                    echo "  slot-${slot}: reference (no kbuild overlay ${kbuild_dtb})" >&2
                else
                    echo "  MISSING slot-${slot} (${device})" >&2
                    return 1
                fi
                ;;
            *)
                echo "  unknown source in slot ${slot}: ${source}" >&2
                return 1
                ;;
        esac

        if [[ "${source}" == "reference" ]]; then
            echo "  slot-${slot}: reference (${device})" >&2
        fi

        [[ -f "${src_path}" ]] || {
            echo "  MISSING ${src_path}" >&2
            return 1
        }
        cp -f "${src_path}" "${out_dir}/slot-${slot}.dtb"
    done < "${map}"

    local count
    count="$(find "${out_dir}" -name 'slot-*.dtb' | wc -l | tr -d ' ')"
    [[ "${count}" -eq 11 ]] || {
        echo "Incomplete chain: ${count}/11 slots" >&2
        return 1
    }

    {
        echo "# DTB chain assembled — ABL multidevice"
        echo "# date: $(date -Iseconds)"
        echo "# kbuild overlay: ${kbuild_dtb_dir:-none}"
        echo "# reference: ${ref_dir}"
        echo ""
        ls -1 "${out_dir}"/slot-*.dtb | while read -r f; do
            printf '%s\t%s\n' "$(basename "$f")" "$(sha256sum "$f" | awk '{print $1}')"
        done
    } > "${out_dir}/MANIFEST.txt"

    export DTB_CHAIN_ASSEMBLED_DIR="${out_dir}"
    echo "  ${count} slots → ${out_dir}/" >&2
}
