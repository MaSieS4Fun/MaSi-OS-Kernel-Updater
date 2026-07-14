# HDMI / DisplayPort audio (AYN SM8550)

## How it works

| Path | Hardware | Kernel routing |
|------|----------|----------------|
| **USB-C DisplayPort** | Dock / monitor with DP Alt Mode | `dp0-dai-link` → **DP0 Playback** → `mdss_dp0` (Armbian `0034` DT) |
| **Physical HDMI jack** (Odin2 / Mini) | Lontium LT8912 bridge | Video via `lontium_lt8912b`; audio is still primarily via **DP0** when the dock outputs HDMI from USB-C |

The QDSP6 stack is built as **modules** (`=m`). MaSi initrd (`efi-clean`) does not bundle them, so `update.sh` installs:

- `/usr/lib/firmware/qcom/sm8550/ayn/<board>/adsp.mbn` (from [armbian/firmware](https://github.com/armbian/firmware))
- `/etc/modules-load.d/masi-qcom-audio.conf`
- `/etc/modprobe.d/masi-qcom-audio.conf`
- `masi-qcom-audio.service` — loads ADSP, then `snd_soc_sc8280xp`
- `depmod -a <release>` after copying kernel modules

Board firmware paths (`odin2mini`, `odin2portal`, `thor`) symlink to `odin2` in the build output.

## After `sudo ./update.sh`

Reboot, then check:

```bash
lsmod | grep -E 'qcom_q6|snd_soc|soundwire'
aplay -l
pactl list sinks short   # PipeWire / PulseAudio
```

Expected PCM devices include internal speakers and **DP0** / HDMI codec nodes when a dock is connected.

## Troubleshooting

### No `snd_soc_sc8280xp` / empty `aplay -l`

```bash
sudo /usr/lib/masi/masi-qcom-audio-init.sh boot
dmesg | grep -iE 'adsp|q6|snd|soundwire|firmware'
ls -l /usr/lib/firmware/qcom/sm8550/ayn/*/adsp.mbn
```

Common causes:

1. **Missing ADSP firmware** — rebuild with `FIRMWARE_SOURCE=download` (default) or copy from a working system: `FIRMWARE_SOURCE=host ./make.sh`
2. **Stale module deps** — re-run `sudo depmod -a "$(uname -r)"`
3. **Wrong ABL device** — DT must match your model (Mini ≠ Odin2)

### Dock video works, no audio on external display

- Confirm PipeWire sees the new sink: `pactl list sinks`
- Select **DP0** / HDMI profile in KDE audio settings
- Kernel side: `cat /proc/asound/cards` and `dmesg | grep -i dp0`

### Odin2 HDMI jack (LT8912) — black screen on dock

```bash
sudo modprobe lontium_lt8912b
```

Module is optional and loaded best-effort by `masi-qcom-audio-init.sh`.

## Build verification

`./make.sh` runs `verify-build`, which checks:

- `qcom_q6v5_adsp.ko`, `snd_soc_sc8280xp.ko`, and related modules in the output tree
- ADSP firmware blobs for all AYN boards in `output/*/firmware/`

## Firmware source

Default: sparse clone of **armbian/firmware** (`qcom/sm8550`, including `ayn/odin2/`).

Override:

```bash
FIRMWARE_SOURCE=host ./make.sh          # copy from this system's /usr/lib/firmware
FIRMWARE_GIT_REF=master ./make.sh       # pin ref (default: master)
```
