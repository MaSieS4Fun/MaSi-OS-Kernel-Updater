# MaSi kernel overlays (post-Armbian)

Applied after the Armbian `sm8550-7.0` patch set via `lib/kbuild/patches.sh`.

| File | Purpose |
|------|---------|
| `1000-add-qcom-haptics-driver.patch` | Qualcomm HV haptics driver (`qcom-hv-haptics`) |
| `1002-haptics-driver-support-periodic-sine-and-fixes.patch` | Haptics sine/periodic + timing fixes |
| `1003-rsinput-add-ff.patch` | Route gamepad FF to PMIC haptics (controller rumble) |
| `1004-haptics-steam-ff-deadlock-fix.patch` | Safer HPWR brake poll + skip erase when idle |
| `1005-thor-ch13726a-reset-polarity-fix.patch` | Thor bottom AMOLED: fix inverted reset GPIO in `panel-ddic-ch13726a` |
| `1006`–`1013` | **Deep suspend** — ROCKNIX PR [#2952](https://github.com/ROCKNIX/distribution/pull/2952) UFS/wake fixes (auto-fetched on first build) |
| `qcs8550-ayn-haptics.dtsi.frag` | Device-tree nodes for `pm8550b` haptics (all AYN boards) |
| `qcs8550-retroidpocket-rp6.dts` | Retroid Pocket 6 board DTS |

Patches `1006`–`1013` are vendored from ROCKNIX PR #2952; re-fetch with `scripts/fetch-rocknix-suspend-patches.py` only for missing files (`--force` replaces vendored copies). Set `SUSPEND_DEEP_PATCHES=0` to skip.

**Apply order:** `1011` (QMP RX LineCfg) runs before `1009`/`1010` so `ufs-qcom.c` hunks still match linux-7.0. The vendored `1011` also anchors on `qmp_ufs_init_registers()` (upstream name) instead of downstream `qmp_ufs_init()`.

Kconfig (also in `config/golden.config`): `CONFIG_INPUT_QCOM_HV_HAPTICS`, `CONFIG_JOYSTICK_RSINPUT`, `CONFIG_INPUT_FF_MEMLESS`.

See `docs/SUSPEND.md` for deep sleep testing.

Gyro/IMU: not present in PMIC DT or upstream AYN DTS; no Linux IIO sensor is enabled on reference images (Batocera/ARMADA). Gyro in games uses userspace/Steam Input unless the MCU protocol is extended in `rsinput`.
