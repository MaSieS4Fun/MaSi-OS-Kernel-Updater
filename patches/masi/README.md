# MaSi kernel overlays (post-Armbian)

Applied after the Armbian `sm8550-7.0` patch set via `lib/kbuild/patches.sh`.

| File | Purpose |
|------|---------|
| `1000-add-qcom-haptics-driver.patch` | Qualcomm HV haptics driver (`qcom-hv-haptics`) |
| `1002-haptics-driver-support-periodic-sine-and-fixes.patch` | Haptics sine/periodic + timing fixes |
| `1003-rsinput-add-ff.patch` | Route gamepad FF to PMIC haptics (controller rumble) |
| `1004-haptics-steam-ff-deadlock-fix.patch` | Safer HPWR brake poll + skip erase when idle |
| `1005-rsinput-ff-workqueue.patch` | Defer gamepad rumble to workqueue; `global_stop` avoids erase deadlocks |
| `qcs8550-ayn-haptics.dtsi.frag` | Device-tree nodes for `pm8550b` haptics (all AYN boards) |
| `qcs8550-retroidpocket-rp6.dts` | Retroid Pocket 6 board DTS |

Kconfig (also in `config/golden.config`): `CONFIG_INPUT_QCOM_HV_HAPTICS`, `CONFIG_JOYSTICK_RSINPUT`, `CONFIG_INPUT_FF_MEMLESS`.

Gyro/IMU: not present in PMIC DT or upstream AYN DTS; no Linux IIO sensor is enabled on reference images (Batocera/ARMADA). Gyro in games uses userspace/Steam Input unless the MCU protocol is extended in `rsinput`.
