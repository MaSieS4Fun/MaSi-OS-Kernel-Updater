#!/usr/bin/env bash
# Download SM8550 firmware subset from public Armbian firmware git (no host image copy).
set -euo pipefail

FIRMWARE_GIT_URL="${FIRMWARE_GIT_URL:-https://github.com/armbian/firmware.git}"
FIRMWARE_GIT_REF="${FIRMWARE_GIT_REF:-master}"

_firmware_cache_dir() {
    echo "${CACHE_DIR}/firmware-armbian"
}

_firmware_sparse_paths() {
    cat <<'EOF'
qcom/sm8550
qcom/a740_sqe.fw
qcom/gmu_gen70200.bin
qcom/vpu
ath12k/WCN7850
qca
regulatory.db
regulatory.db.p7s
renesas_usb_fw.mem
rtl_nic
EOF
}

download_firmware_sm8550() {
    local dest="$1" cache work ref
    cache="$(_firmware_cache_dir)"
    work="${CACHE_DIR}/.firmware-download-$$"

    if [[ -d "${cache}/qcom/sm8550" ]]; then
        echo "==> firmware cache: ${cache}" >&2
        _firmware_stage_copy "${cache}" "${dest}"
        return 0
    fi

    command -v git >/dev/null 2>&1 || {
        echo "Install git to download firmware from ${FIRMWARE_GIT_URL}" >&2
        return 1
    }

    echo "==> Downloading firmware from ${FIRMWARE_GIT_URL} (${FIRMWARE_GIT_REF})..." >&2
    rm -rf "${work}"
    ref="${FIRMWARE_GIT_REF}"
    if ! git clone --depth 1 --branch "${ref}" \
        --filter=blob:none --sparse "${FIRMWARE_GIT_URL}" "${work}" >&2; then
        if [[ "${ref}" != "master" ]]; then
            echo "  retry: branch master" >&2
            rm -rf "${work}"
            ref="master"
            git clone --depth 1 --branch "${ref}" \
                --filter=blob:none --sparse "${FIRMWARE_GIT_URL}" "${work}" >&2 || return 1
        else
            return 1
        fi
    fi

    [[ -d "${work}/.git" ]] || {
        echo "Firmware download failed — clone directory missing" >&2
        rm -rf "${work}"
        return 1
    }

    (
        cd "${work}"
        _firmware_sparse_paths | git sparse-checkout set --stdin
        git checkout "${ref}" >/dev/null 2>&1 || true
    ) || {
        rm -rf "${work}"
        return 1
    }

    [[ -d "${work}/qcom/sm8550" ]] || {
        echo "Firmware download incomplete — no qcom/sm8550 in checkout" >&2
        rm -rf "${work}"
        return 1
    }

    rm -rf "${cache}"
    mv "${work}" "${cache}"
    _firmware_stage_copy "${cache}" "${dest}"
}

_firmware_stage_copy() {
    local src="$1" dest="$2" path

    rm -rf "${dest}"
    mkdir -p "${dest}"

    while IFS= read -r path; do
        [[ -n "${path}" ]] || continue
        [[ -e "${src}/${path}" ]] || continue
        mkdir -p "${dest}/$(dirname "${path}")"
        cp -a "${src}/${path}" "${dest}/${path}"
        echo "  + ${path}" >&2
    done < <(_firmware_sparse_paths)

    local ayn="${dest}/qcom/sm8550/ayn"
    if [[ -d "${ayn}/odin2" ]]; then
        for dev in odin2mini odin2portal thor; do
            [[ -e "${ayn}/${dev}" ]] || ln -sfn odin2 "${ayn}/${dev}"
        done
    elif [[ ! -f "${ayn}/odin2/adsp.mbn" ]]; then
        echo "  WARNING: no qcom/sm8550/ayn/odin2 in firmware checkout" >&2
    fi

    local n
    n="$(find "${dest}" -type f 2>/dev/null | wc -l | tr -d ' ')"
    echo "  ${n} files ($(du -sh "${dest}" | cut -f1))" >&2
    [[ "${n}" -gt 0 ]]
}
