#!/usr/bin/env bash
# Copy SM8550 firmware from system → output/firmware/ (manual install).
set -euo pipefail

_system_firmware_root() {
    local p
    for p in /usr/lib/firmware /lib/firmware; do
        [[ -d "${p}/qcom/sm8550" || -d "${p}/qcom" ]] && echo "${p}" && return 0
    done
    echo "/usr/lib/firmware"
}

prepare_firmware_masi() {
    local out_dir="$1"
    local fw_out="${out_dir}/firmware"
    local system_src path

    system_src="$(_system_firmware_root)"
    rm -rf "${fw_out}"
    mkdir -p "${fw_out}"

    echo "==> firmware → ${fw_out}/ (from ${system_src})" >&2

    for path in \
        qcom/sm8550 \
        qcom/a740_sqe.fw \
        qcom/gmu_gen70200.bin \
        qcom/vpu \
        ath12k/WCN7850 \
        qca \
        regulatory.db \
        regulatory.db.p7s \
        renesas_usb_fw.mem \
        rtl_nic; do
        if [[ -e "${system_src}/${path}" ]]; then
            mkdir -p "${fw_out}/$(dirname "${path}")"
            cp -a "${system_src}/${path}" "${fw_out}/${path}"
            echo "  + ${path}" >&2
        fi
    done

    local ayn="${fw_out}/qcom/sm8550/ayn"
    if [[ -d "${ayn}/odin2" ]]; then
        for dev in odin2mini odin2portal thor; do
            [[ -e "${ayn}/${dev}" ]] || ln -sfn odin2 "${ayn}/${dev}"
        done
    fi

    local n
    n="$(find "${fw_out}" -type f 2>/dev/null | wc -l | tr -d ' ')"
    echo "  ${n} files ($(du -sh "${fw_out}" | cut -f1))" >&2
    [[ "${n}" -gt 0 ]] || {
        echo "WARNING: empty firmware — building off-device?" >&2
        return 0
    }
}
