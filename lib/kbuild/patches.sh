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

_ensure_dtb_in_makefile() {
    local mk="$1" dtb="$2"
    grep -q "${dtb}" "${mk}" && return 0
    if grep -q 'qcs8550-ayn-odin2portal\.dtb' "${mk}"; then
        sed -i "/qcs8550-ayn-odin2portal\.dtb/a dtb-\$(CONFIG_ARCH_QCOM)\t+= ${dtb}" "${mk}"
    elif grep -q 'qcs8550-ayn-odin2mini\.dtb' "${mk}"; then
        sed -i "/qcs8550-ayn-odin2mini\.dtb/a dtb-\$(CONFIG_ARCH_QCOM)\t+= ${dtb}" "${mk}"
    elif grep -q 'qcs8550-ayn-odin2\.dtb' "${mk}"; then
        sed -i "/qcs8550-ayn-odin2\.dtb/a dtb-\$(CONFIG_ARCH_QCOM)\t+= ${dtb}" "${mk}"
    else
        sed -i "/qcs8550-aim300-aiot\.dtb/a dtb-\$(CONFIG_ARCH_QCOM)\t+= ${dtb}" "${mk}"
    fi
}

_verify_masi_dtb_sources() {
    local src_dir="$1" devices="${ROOT}/config/devices.conf" mk
    local line dtb dts missing=0

    mk="${src_dir}/arch/arm64/boot/dts/qcom/Makefile"
    [[ -f "${mk}" ]] || {
        echo "ERROR: missing ${mk} after patches" >&2
        return 1
    }

    while IFS='|' read -r _id dtb _label; do
        [[ -z "${_id:-}" || "${_id}" =~ ^# ]] && continue
        [[ -z "${dtb:-}" || "${dtb}" == DTB_FILENAME ]] && continue
        [[ "${dtb}" == *.dtb ]] || continue
        dts="${dtb%.dtb}.dts"
        if [[ ! -f "${src_dir}/arch/arm64/boot/dts/qcom/${dts}" ]]; then
            echo "ERROR: missing device tree source ${dts} (required for ${dtb})" >&2
            missing=$((missing + 1))
            continue
        fi
        if ! grep -q "${dtb}" "${mk}"; then
            echo "  FIX  adding ${dtb} to dts/qcom/Makefile" >&2
            _ensure_dtb_in_makefile "${mk}" "${dtb}"
        fi
    done < "${devices}"

    [[ "${missing}" -eq 0 ]] || return 1
}

_apply_pending_ayn_dtb_patches() {
    local src_dir="$1" patch_dir="$2" patch base applied=0
    shopt -s nullglob
    for patch in "${patch_dir}"/00*-arm64-dts-qcom-Add-AYN-*.patch; do
        base="$(basename "${patch}")"
        if patch -p1 --dry-run -d "${src_dir}" -f < "${patch}" >/dev/null 2>&1; then
            echo "  APPLY ${base}" >&2
            patch -p1 -d "${src_dir}" -f < "${patch}" >/dev/null 2>&1 && applied=$((applied + 1))
        fi
    done
    shopt -u nullglob
    [[ "${applied}" -gt 0 ]]
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
        apply_masi_extra_dts "${src_dir}"
        apply_masi_haptics_dtsi "${src_dir}" || true
        apply_masi_kernel_patches "${src_dir}" || true
        verify_masi_haptics_stack "${src_dir}" || return 1
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

    echo "==> Ensuring AYN device tree patches..." >&2
    _apply_pending_ayn_dtb_patches "${src_dir}" "${patch_dir}" || true
    apply_masi_extra_dts "${src_dir}" || true
    apply_masi_haptics_dtsi "${src_dir}" || failed=1
    apply_masi_kernel_patches "${src_dir}" || failed=1
    verify_masi_haptics_stack "${src_dir}" || failed=1
    _verify_masi_dtb_sources "${src_dir}" || failed=1

    if [[ "${failed}" -gt 0 ]] && _verify_masi_dtb_sources "${src_dir}" 2>/dev/null; then
        local non_dtb_fail=0 f base
        shopt -s nullglob
        for f in "${OUTPUT_DIR}"/patch-fail-*.txt; do
            base="$(basename "${f}" .txt)"
            base="${base#patch-fail-}"
            [[ "${base}" == *arm64-dts-qcom-Add-AYN-* ]] || non_dtb_fail=1
        done
        shopt -u nullglob
        [[ "${non_dtb_fail}" -eq 0 ]] && failed=0
    fi

    if [[ "${failed}" -gt 0 ]]; then
        echo "BUILD ABORTED — see ${log} and patch-fail-*.txt in ${OUTPUT_DIR}/" >&2
        echo "  Tip: rm -rf ${src_dir} .cache/armbian-patches/${patch_set} if inconsistent." >&2
        [[ "${PATCH_POLICY}" == "tolerant" ]] && return 0
        return 1
    fi

    touch "${stamp}"
}

# HV haptics + gamepad rumble (Batocera-derived DT fragment for all AYN SM8550 boards).
apply_masi_haptics_dtsi() {
    local src_dir="$1"
    local dtsi="${src_dir}/arch/arm64/boot/dts/qcom/qcs8550-ayn-common.dtsi"
    local frag="${ROOT}/patches/masi/qcs8550-ayn-haptics.dtsi.frag"
    local tmp marker='&pm8550b_eusb2_repeater'

    [[ -f "${dtsi}" && -f "${frag}" ]] || return 0
    if grep -q 'qcom,hv-haptics' "${dtsi}"; then
        echo "  SKIP MaSi haptics DT (already present)" >&2
        return 0
    fi
    if ! grep -q "${marker}" "${dtsi}"; then
        echo "  FAIL MaSi haptics DT: marker ${marker} not in ${dtsi}" >&2
        return 1
    fi

    if ! grep -q 'dt-bindings/input/qcom,hv-haptics.h' "${dtsi}"; then
        sed -i '/dt-bindings\/leds\/common.h/a #include <dt-bindings/input/qcom,hv-haptics.h>' "${dtsi}"
    fi

    tmp="$(mktemp)"
    awk -v marker="${marker}" -v frag="${frag}" '
        $0 ~ marker && !done {
            while ((getline line < frag) > 0)
                print line
            close(frag)
            done = 1
        }
        { print }
    ' "${dtsi}" > "${tmp}"
    mv "${tmp}" "${dtsi}"
    echo "  OK   MaSi qcs8550-ayn-common haptics DT" >&2
}

apply_masi_kernel_patches() {
    local src_dir="$1" patch_dir="${ROOT}/patches/masi"
    local patch base failed=0 applied=0 skipped=0

    [[ -d "${patch_dir}" ]] || return 0

    echo "==> MaSi kernel patches (gamepad haptics)" >&2
    shopt -s nullglob
    for patch in "${patch_dir}"/[0-9]*.patch; do
        base="$(basename "${patch}")"
        if [[ "${base}" == "1001-qcom-haptics-trace-7.0.patch" ]]; then
            echo "  SKIP ${base} (folded into 1000 base patch)" >&2
            skipped=$((skipped + 1))
            continue
        fi
        if [[ "${base}" == "1003-rsinput-add-ff.patch" ]]; then
            if apply_masi_rsinput_ff_bridge "${src_dir}"; then
                echo "  OK   ${base}" >&2
                applied=$((applied + 1))
            else
                echo "  FAIL ${base}" >&2
                failed=$((failed + 1))
            fi
            continue
        fi
        if patch -p1 --dry-run -d "${src_dir}" -f < "${patch}" >/dev/null 2>&1; then
            patch -p1 -d "${src_dir}" -f < "${patch}" >/dev/null 2>&1 && {
                echo "  OK   ${base}" >&2
                applied=$((applied + 1))
            } || { echo "  FAIL ${base}" >&2; failed=$((failed + 1)); }
        elif patch -p1 --dry-run -R -d "${src_dir}" -f < "${patch}" >/dev/null 2>&1; then
            echo "  SKIP ${base}" >&2
            skipped=$((skipped + 1))
        else
            echo "  FAIL ${base}" >&2
            failed=$((failed + 1))
        fi
    done
    shopt -u nullglob
    echo "==> MaSi patches: ${applied} ok, ${skipped} skip, ${failed} fail" >&2
    [[ "${failed}" -eq 0 ]]
}

apply_masi_rsinput_ff_bridge() {
    local src_dir="$1"
    local rsinput="${src_dir}/drivers/input/joystick/rsinput.c"
    local haptics="${src_dir}/drivers/input/misc/qcom-hv-haptics.c"

    [[ -f "${rsinput}" && -f "${haptics}" ]] || return 1

    python3 - "${rsinput}" "${haptics}" <<'PY'
from pathlib import Path
import sys

rsinput = Path(sys.argv[1])
haptics = Path(sys.argv[2])

def ensure_once(text, needle, insert_before=None, insert_after=None, block=""):
    if needle in text:
        return text, True
    if insert_before and insert_before in text:
        return text.replace(insert_before, block + insert_before, 1), True
    if insert_after and insert_after in text:
        return text.replace(insert_after, insert_after + block, 1), True
    return text, False

ok = True

rt = rsinput.read_text()
rt, found = ensure_once(
    rt,
    'static bool rumble_enable = true;',
    insert_before='static const unsigned int keymap[] = {\n',
    block='static bool rumble_enable = true;\nmodule_param(rumble_enable, bool, 0644);\nMODULE_PARM_DESC(rumble_enable, "Enable gamepad rumble via PMIC haptics");\n\n'
)
ok &= found

rt, found = ensure_once(
    rt,
    'extern int qcom_spmi_haptics_global_set_gain(u16 gain);',
    insert_before='static int rsinput_probe(struct serdev_device *serdev) {\n',
    block=(
        'extern int qcom_spmi_haptics_global_upload(struct ff_effect *effect);\n'
        'extern int qcom_spmi_haptics_global_playback(int effect_id, int val);\n'
        'extern int qcom_spmi_haptics_global_stop(void);\n\n'
        'extern int qcom_spmi_haptics_global_set_gain(u16 gain);\n\n'
        'struct rsinput_rumble_req {\n'
        '\tu16 magnitude;\n'
        '\tu16 length_ms;\n'
        '\tbool stop;\n'
        '};\n\n'
        'static struct rsinput_rumble_req rumble_req;\n'
        'static struct work_struct rumble_work;\n'
        'static DEFINE_MUTEX(rumble_work_lock);\n\n'
        'static void rsinput_rumble_work_fn(struct work_struct *work)\n'
        '{\n'
        '\tstruct rsinput_rumble_req req;\n'
        '\tstruct ff_effect hfx = { 0 };\n'
        '\tu16 level;\n'
        '\tint ret;\n\n'
        '\tmutex_lock(&rumble_work_lock);\n'
        '\treq = rumble_req;\n'
        '\tmutex_unlock(&rumble_work_lock);\n\n'
        '\tif (!rumble_enable)\n'
        '\t\treturn;\n'
        '\tif (req.stop || !req.magnitude) {\n'
        '\t\tqcom_spmi_haptics_global_stop();\n'
        '\t\treturn;\n'
        '\t}\n\n'
        '\thfx.type = FF_CONSTANT;\n'
        '\thfx.id = 0;\n'
        '\thfx.replay.length = req.length_ms ? req.length_ms : 250;\n'
        '\tlevel = max_t(u16, req.magnitude, 0x2000);\n'
        '\thfx.u.constant.level = clamp(level >> 1, 1, 0x7fff);\n\n'
        '\tret = qcom_spmi_haptics_global_upload(&hfx);\n'
        '\tif (ret < 0)\n'
        '\t\treturn;\n'
        '\tret = qcom_spmi_haptics_global_set_gain(level);\n'
        '\tif (ret < 0)\n'
        '\t\treturn;\n'
        '\tqcom_spmi_haptics_global_playback(0, 1);\n'
        '}\n\n'
        'static void rsinput_rumble_cancel(void *unused)\n'
        '{\n'
        '\tcancel_work_sync(&rumble_work);\n'
        '}\n\n'
        'static void rsinput_queue_rumble(u16 magnitude, u16 length_ms, bool stop)\n'
        '{\n'
        '\tmutex_lock(&rumble_work_lock);\n'
        '\trumble_req.magnitude = magnitude;\n'
        '\trumble_req.length_ms = length_ms;\n'
        '\trumble_req.stop = stop;\n'
        '\tmutex_unlock(&rumble_work_lock);\n'
        '\tschedule_work(&rumble_work);\n'
        '}\n\n'
        'static int rsinput_rumble_play_effect(struct input_dev *dev, void *data,\n'
        '\t\t\t\t      struct ff_effect *effect)\n'
        '{\n'
        '\tu16 magnitude = 0;\n'
        '\tu16 length_ms = 0;\n\n'
        '\tif (!rumble_enable)\n'
        '\t\treturn 0;\n\n'
        '\tif (effect->type == FF_RUMBLE) {\n'
        '\t\tmagnitude = max_t(u16, effect->u.rumble.strong_magnitude,\n'
        '\t\t\t\t\t  effect->u.rumble.weak_magnitude);\n'
        '\t\tlength_ms = effect->replay.length;\n'
        '\t} else if (effect->type == FF_PERIODIC) {\n'
        '\t\tmagnitude = abs(effect->u.periodic.magnitude);\n'
        '\t\tlength_ms = effect->replay.length ? effect->replay.length : 30000;\n'
        '\t} else {\n'
        '\t\treturn 0;\n'
        '\t}\n\n'
        '\tif (!magnitude) {\n'
        '\t\trsinput_queue_rumble(0, 0, true);\n'
        '\t\treturn 0;\n'
        '\t}\n\n'
        '\trsinput_queue_rumble(magnitude, length_ms, false);\n'
        '\treturn 0;\n'
        '}\n\n'
    )
)
ok &= found

rt, found = ensure_once(
    rt,
    'INIT_WORK(&rumble_work, rsinput_rumble_work_fn);',
    insert_before='    error = input_register_device(drv->input);\n',
    block=(
        '    INIT_WORK(&rumble_work, rsinput_rumble_work_fn);\n'
        '    devm_add_action(&serdev->dev, rsinput_rumble_cancel, NULL);\n\n'
    )
)
ok &= found

# Replace legacy synchronous play_effect if present from an older bridge revision.
legacy_play_effect = (
    'static int rsinput_rumble_play_effect(struct input_dev *dev, void *data,\n'
    '\t\t\t\t      struct ff_effect *effect)\n'
    '{\n'
    '\tstruct ff_effect hfx = { 0 };\n'
    '\tu16 magnitude;\n'
    '\tint ret;\n\n'
    '\tif (!rumble_enable)\n'
    '\t\treturn 0;\n'
    '\tif (effect->type != FF_RUMBLE)\n'
    '\t\treturn 0;\n\n'
    '\tmagnitude = max_t(u16, effect->u.rumble.strong_magnitude,\n'
    '\t\t\t\t effect->u.rumble.weak_magnitude);\n'
    '\tif (!magnitude)\n'
    '\t\treturn qcom_spmi_haptics_global_playback(0, 0);\n\n'
    '\thfx.type = FF_CONSTANT;\n'
    '\thfx.id = 0;\n'
    '\thfx.replay.length = effect->replay.length ? effect->replay.length : 250;\n'
    '\thfx.u.constant.level = max_t(u16, 1, magnitude >> 1);\n\n'
    '\tret = qcom_spmi_haptics_global_upload(&hfx);\n'
    '\tif (ret < 0)\n'
    '\t\treturn ret;\n'
    '\tret = qcom_spmi_haptics_global_set_gain(magnitude);\n'
    '\tif (ret < 0)\n'
    '\t\treturn ret;\n'
    '\treturn qcom_spmi_haptics_global_playback(0, 1);\n'
    '}\n\n'
)
if legacy_play_effect in rt:
    rt = rt.replace(legacy_play_effect, '')

rt, found = ensure_once(
    rt,
    'input_set_capability(drv->input, EV_FF, FF_RUMBLE);',
    insert_before='    error = input_register_device(drv->input);\n',
    block=(
        '    input_set_capability(drv->input, EV_FF, FF_RUMBLE);\n'
        '    input_set_capability(drv->input, EV_FF, FF_PERIODIC);\n\n'
        '    error = input_ff_create_memless(drv->input, drv, rsinput_rumble_play_effect);\n'
        '    if (error) {\n'
        '        serdev_device_close(serdev);\n'
        '        return dev_err_probe(&serdev->dev, error, "Unable to create force feedback device\\n");\n'
        '    }\n\n'
    )
)
ok &= found

ht = haptics.read_text()
ht, found = ensure_once(
    ht,
    '#include <linux/export.h>\n',
    insert_after='#include <linux/vmalloc.h>\n',
    block='#include <linux/export.h>\n'
)
ok &= found

ht, found = ensure_once(
    ht,
    'static struct haptics_chip *global_haptics;',
    insert_before='static inline int get_max_fifo_samples(struct haptics_chip *chip)\n',
    block='static struct haptics_chip *global_haptics;\n\n'
)
ok &= found

ht, found = ensure_once(
    ht,
    '\tglobal_haptics = chip;\n',
    insert_before='\treturn 0;\n'
                 'destroy_ff:\n',
    block='\tglobal_haptics = chip;\n\n'
)
ok &= found

ht, found = ensure_once(
    ht,
    '\tif (global_haptics == chip)\n'
    '\t\tglobal_haptics = NULL;\n',
    insert_before='\tunregister_hboost_event_notifier(&chip->hboost_nb);\n',
    block='\tif (global_haptics == chip)\n\t\tglobal_haptics = NULL;\n\n'
)
ok &= found

legacy_spinlock_bridge = (
    '\tspin_lock_irq(&global_haptics->input_dev->event_lock);\n'
    '\tret = global_haptics->input_dev->ff->upload(global_haptics->input_dev,\n'
    '\t\t\t\t\t\t    effect, NULL);\n'
    '\tspin_unlock_irq(&global_haptics->input_dev->event_lock);\n'
)
mutex_bridge = (
    '\tmutex_lock(&global_ff_mutex);\n'
    '\tret = global_haptics->input_dev->ff->upload(global_haptics->input_dev,\n'
    '\t\t\t\t\t\t    effect, NULL);\n'
    '\tmutex_unlock(&global_ff_mutex);\n'
)
if legacy_spinlock_bridge in ht:
    ht = ht.replace(legacy_spinlock_bridge, mutex_bridge)
    ht = ht.replace(
        '\tspin_lock_irq(&global_haptics->input_dev->event_lock);\n'
        '\tif (val != 0)\n'
        '\t\tret = global_haptics->input_dev->ff->playback(global_haptics->input_dev,\n'
        '\t\t\t\t\t\t\t      effect_id, val);\n'
        '\telse\n'
        '\t\tret = global_haptics->input_dev->ff->erase(global_haptics->input_dev,\n'
        '\t\t\t\t\t\t\t   effect_id);\n'
        '\tspin_unlock_irq(&global_haptics->input_dev->event_lock);\n',
        '\tmutex_lock(&global_ff_mutex);\n'
        '\tif (val != 0) {\n'
        '\t\tret = global_haptics->input_dev->ff->playback(global_haptics->input_dev,\n'
        '\t\t\t\t\t\t\t      effect_id, val);\n'
        '\t} else if (!global_haptics->chip_is_playing) {\n'
        '\t\tret = 0;\n'
        '\t} else {\n'
        '\t\tret = global_haptics->input_dev->ff->erase(global_haptics->input_dev,\n'
        '\t\t\t\t\t\t\t   effect_id);\n'
        '\t}\n'
        '\tmutex_unlock(&global_ff_mutex);\n'
    )
    ht = ht.replace(
        '\tspin_lock_irq(&global_haptics->input_dev->event_lock);\n'
        '\tgain = clamp(gain, 0x4000, 0x7fff);\n'
        '\tglobal_haptics->input_dev->ff->set_gain(global_haptics->input_dev, gain);\n'
        '\tspin_unlock_irq(&global_haptics->input_dev->event_lock);\n',
        '\tmutex_lock(&global_ff_mutex);\n'
        '\tgain = clamp(gain, 0x4000, 0x7fff);\n'
        '\tglobal_haptics->input_dev->ff->set_gain(global_haptics->input_dev, gain);\n'
        '\tmutex_unlock(&global_ff_mutex);\n'
    )
    if 'static DEFINE_MUTEX(global_ff_mutex);' not in ht:
        ht = ht.replace(
            'static struct haptics_chip *global_haptics;\n',
            'static struct haptics_chip *global_haptics;\nstatic DEFINE_MUTEX(global_ff_mutex);\n',
            1
        )

ht, found = ensure_once(
    ht,
    'EXPORT_SYMBOL_GPL(qcom_spmi_haptics_global_playback);',
    insert_before='MODULE_DESCRIPTION("Qualcomm Technologies, Inc. High-Voltage Haptics driver");\n',
    block=(
        'int qcom_spmi_haptics_global_upload(struct ff_effect *effect)\n'
        '{\n'
        '\tint ret;\n\n'
        '\tif (!global_haptics)\n'
        '\t\treturn -ENODEV;\n\n'
        '\tmutex_lock(&global_ff_mutex);\n'
        '\tret = global_haptics->input_dev->ff->upload(global_haptics->input_dev,\n'
        '\t\t\t\t\t\t    effect, NULL);\n'
        '\tmutex_unlock(&global_ff_mutex);\n\n'
        '\treturn ret;\n'
        '}\n'
        'EXPORT_SYMBOL_GPL(qcom_spmi_haptics_global_upload);\n\n'
        'int qcom_spmi_haptics_global_playback(int effect_id, int val)\n'
        '{\n'
        '\tint ret;\n\n'
        '\tif (!global_haptics)\n'
        '\t\treturn -ENODEV;\n\n'
        '\tmutex_lock(&global_ff_mutex);\n'
        '\tif (val != 0) {\n'
        '\t\tret = global_haptics->input_dev->ff->playback(global_haptics->input_dev,\n'
        '\t\t\t\t\t\t\t      effect_id, val);\n'
        '\t} else if (!global_haptics->chip_is_playing) {\n'
        '\t\tret = 0;\n'
        '\t} else {\n'
        '\t\tret = global_haptics->input_dev->ff->erase(global_haptics->input_dev,\n'
        '\t\t\t\t\t\t\t   effect_id);\n'
        '\t}\n'
        '\tmutex_unlock(&global_ff_mutex);\n\n'
        '\treturn ret;\n'
        '}\n'
        'EXPORT_SYMBOL_GPL(qcom_spmi_haptics_global_playback);\n\n'
        'int qcom_spmi_haptics_global_set_gain(u16 gain)\n'
        '{\n'
        '\tif (!global_haptics)\n'
        '\t\treturn -ENODEV;\n\n'
        '\tmutex_lock(&global_ff_mutex);\n'
        '\tgain = clamp(gain, 0x4000, 0x7fff);\n'
        '\tglobal_haptics->input_dev->ff->set_gain(global_haptics->input_dev, gain);\n'
        '\tmutex_unlock(&global_ff_mutex);\n\n'
        '\treturn 0;\n'
        '}\n'
        'EXPORT_SYMBOL_GPL(qcom_spmi_haptics_global_set_gain);\n\n'
        'int qcom_spmi_haptics_global_stop(void)\n'
        '{\n'
        '\tstruct haptics_play_info *play;\n\n'
        '\tif (!global_haptics)\n'
        '\t\treturn -ENODEV;\n\n'
        '\tplay = &global_haptics->play;\n\n'
        '\tmutex_lock(&global_ff_mutex);\n'
        '\tif (!global_haptics->chip_is_playing) {\n'
        '\t\tglobal_haptics->chip_effect_loaded = false;\n'
        '\t\tmutex_unlock(&global_ff_mutex);\n'
        '\t\treturn 0;\n'
        '\t}\n\n'
        '\tmutex_lock(&play->lock);\n'
        '\tcancel_delayed_work_sync(&global_haptics->stop_work);\n'
        '\thaptics_enable_play(global_haptics, false);\n'
        '\tglobal_haptics->chip_effect_loaded = false;\n'
        '\tmutex_unlock(&play->lock);\n'
        '\tmutex_unlock(&global_ff_mutex);\n\n'
        '\treturn 0;\n'
        '}\n'
        'EXPORT_SYMBOL_GPL(qcom_spmi_haptics_global_stop);\n\n'
    )
)
ok &= found

ht, found = ensure_once(
    ht,
    'static DEFINE_MUTEX(global_ff_mutex);',
    insert_after='static struct haptics_chip *global_haptics;\n',
    block='static DEFINE_MUTEX(global_ff_mutex);\n'
)
ok &= found

if ok:
    rsinput.write_text(rt)
    haptics.write_text(ht)
    sys.exit(0)
sys.exit(1)
PY
}

verify_masi_haptics_stack() {
    local src_dir="$1"
    local rsinput="${src_dir}/drivers/input/joystick/rsinput.c"
    local haptics="${src_dir}/drivers/input/misc/qcom-hv-haptics.c"
    local trace="${src_dir}/include/trace/events/qcom_haptics.h"
    local failed=0

    echo "==> Verify MaSi haptics stack" >&2

    if grep -q 'input_set_capability(drv->input, EV_FF, FF_RUMBLE)' "${rsinput}" \
        && grep -q 'input_ff_create_memless(drv->input, drv, rsinput_rumble_play_effect)' "${rsinput}" \
        && grep -q 'qcom_spmi_haptics_global_set_gain' "${rsinput}" \
        && grep -q 'schedule_work(&rumble_work)' "${rsinput}" \
        && grep -q 'qcom_spmi_haptics_global_stop' "${rsinput}"; then
        echo "  OK   rsinput exposes EV_FF" >&2
    else
        echo "  FAIL rsinput missing EV_FF integration" >&2
        failed=1
    fi

    if grep -q 'EXPORT_SYMBOL_GPL(qcom_spmi_haptics_global_playback)' "${haptics}" \
        && grep -q 'static struct haptics_chip \*global_haptics' "${haptics}" \
        && grep -q 'mutex_lock(&global_ff_mutex)' "${haptics}" \
        && grep -q 'EXPORT_SYMBOL_GPL(qcom_spmi_haptics_global_stop)' "${haptics}"; then
        echo "  OK   qcom-hv-haptics exports mutex-safe global playback hooks" >&2
    else
        echo "  FAIL qcom-hv-haptics missing mutex-safe exported playback hooks" >&2
        failed=1
    fi

    if grep -q '__assign_str(id_name);' "${trace}"; then
        echo "  OK   qcom_haptics trace API matches kernel 7.0" >&2
    else
        echo "  FAIL qcom_haptics trace API not fixed for kernel 7.0" >&2
        failed=1
    fi

    [[ "${failed}" -eq 0 ]]
}

# Retroid Pocket 6 DTB — public DTS (LineageOS kernel-ack, adapted for Armbian ayn-common).
apply_masi_extra_dts() {
    local src_dir="$1"
    local extra="${ROOT}/patches/masi/qcs8550-retroidpocket-rp6.dts"
    local mk="${src_dir}/arch/arm64/boot/dts/qcom/Makefile"
    local dest="${src_dir}/arch/arm64/boot/dts/qcom/qcs8550-retroidpocket-rp6.dts"

    [[ -f "${extra}" ]] || return 0
    [[ -f "${mk}" ]] || return 1

    cp -f "${extra}" "${dest}"
    if ! grep -q 'qcs8550-retroidpocket-rp6\.dtb' "${mk}"; then
        sed -i '/qcs8550-ayn-thor\.dtb/a dtb-$(CONFIG_ARCH_QCOM) += qcs8550-retroidpocket-rp6.dtb' "${mk}"
    fi
    echo "  OK   MaSi qcs8550-retroidpocket-rp6.dts" >&2
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
    local gov="${CPUFREQ_GOVERNOR:-schedutil}"
    [[ -f "${cfg}" && -x "${sc}" ]] || return 0

    echo "==> Overrides gaming kconfig (cpufreq: ${gov})" >&2
    "${sc}" --file "${cfg}" \
        --enable SCHED_SMT --enable SCHED_MC --enable SCHED_CLUSTER \
        --disable PSI \
        --enable MMC_SDHCI_MSM_DOWNSTREAM \
        --enable ENERGY_MODEL \
        --enable CC_OPTIMIZE_FOR_PERFORMANCE \
        --disable CC_OPTIMIZE_FOR_SIZE 2>/dev/null || true

    case "${gov}" in
        performance)
            "${sc}" --file "${cfg}" \
                --set-str CPU_FREQ_DEFAULT_GOV_PERFORMANCE \
                --disable CPU_FREQ_DEFAULT_GOV_SCHEDUTIL \
                --enable CPU_FREQ_GOV_PERFORMANCE 2>/dev/null || true
            ;;
        *)
            "${sc}" --file "${cfg}" \
                --set-str CPU_FREQ_DEFAULT_GOV_SCHEDUTIL \
                --disable CPU_FREQ_DEFAULT_GOV_PERFORMANCE \
                --enable CPU_FREQ_GOV_SCHEDUTIL 2>/dev/null || true
            ;;
    esac

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
        BACKLIGHT_ODIN2MINI BACKLIGHT_SY7758 \
        DRM_PANEL_RETROID_POCKET_6 \
        JOYSTICK_RSINPUT LEDS_HTR3212 INPUT_FF_MEMLESS \
        INPUT_QCOM_HV_HAPTICS SERIAL_DEV_BUS
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
