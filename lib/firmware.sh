#!/usr/bin/env bash
# Copy or download SM8550 firmware → output/firmware/
set -euo pipefail

_system_firmware_root() {
    local p
    for p in /usr/lib/firmware /lib/firmware; do
        [[ -d "${p}/qcom/sm8550" || -d "${p}/qcom" ]] && echo "${p}" && return 0
    done
    return 1
}

prepare_firmware_masi() {
    local out_dir="$1"
    local fw_out="${out_dir}/firmware"
    local mode="${FIRMWARE_SOURCE:-download}"

    rm -rf "${fw_out}"
    mkdir -p "${fw_out}"

    case "${mode}" in
        host)
            local system_src path
            system_src="$(_system_firmware_root)" || {
                echo "FIRMWARE_SOURCE=host but no qcom firmware on system" >&2
                return 1
            }
            echo "==> firmware → ${fw_out}/ (from ${system_src})" >&2
            for path in \
                qcom/sm8550 qcom/a740_sqe.fw qcom/gmu_gen70200.bin qcom/vpu \
                ath12k/WCN7850 qca regulatory.db regulatory.db.p7s \
                renesas_usb_fw.mem rtl_nic; do
                [[ -e "${system_src}/${path}" ]] || continue
                mkdir -p "${fw_out}/$(dirname "${path}")"
                cp -a "${system_src}/${path}" "${fw_out}/${path}"
                echo "  + ${path}" >&2
            done
            ;;
        download|*)
            # shellcheck source=lib/firmware-download.sh
            source "${ROOT}/lib/firmware-download.sh"
            download_firmware_sm8550 "${fw_out}" || return 1
            ;;
    esac

    local n ayn="${fw_out}/qcom/sm8550/ayn"
    n="$(find "${fw_out}" -type f 2>/dev/null | wc -l | tr -d ' ')"
    echo "  ${n} files ($(du -sh "${fw_out}" | cut -f1))" >&2
    for dev in odin2 odin2mini odin2portal thor; do
        [[ -f "${ayn}/${dev}/adsp.mbn" ]] || {
            echo "  WARNING: missing firmware qcom/sm8550/ayn/${dev}/adsp.mbn" >&2
        }
    done
    [[ "${n}" -gt 0 ]] || {
        echo "ERROR: empty firmware output" >&2
        return 1
    }
}
