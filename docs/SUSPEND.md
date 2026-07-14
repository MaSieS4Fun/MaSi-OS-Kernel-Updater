# SM8550 deep suspend (MaSi)

Enables **platform deep sleep** (`mem` / `deep`) on AYN handhelds. Ported from [ROCKNIX/distribution#2952](https://github.com/ROCKNIX/distribution/pull/2952) (tested on Thor).

## What the kernel fixes

SM8550 UFS is **`no_phy_retention`**: on deep suspend the storage link powers off and must **cold-relink** on resume. Stock drivers could leave UFS completions stuck → read-only root, `-110` I/O errors, or hang.

MaSi applies ROCKNIX patches `1006`–`1013` in `patches/masi/` (auto-downloaded on first `./make.sh` if missing):

| Patch | Area |
|-------|------|
| 1006 | `ufshcd` PM relink completion drain |
| 1007 | `ufs-qcom` host_reset IRQ balance |
| 1008 | hibern8 exit error propagation (clk scale) |
| 1009 | disable HW auto-hibern8 vs SW clk-gating |
| 1010 | keep M-PHY powered on hibern8 park |
| 1011 | QMP PHY RX LineCfg during link startup |
| 1012 | IPCC: drop `IRQF_NO_SUSPEND` |
| 1013 | Thor TSENS: skip noisy uplow wake IRQ |

**Not included** (optional in ROCKNIX): UFS inline crypto / ICE patches — not required for suspend itself.

## Build defaults

In `config/defaults.conf`:

| Variable | Default | Effect |
|----------|---------|--------|
| `SUSPEND_DEEP_PATCHES` | `1` | Fetch + apply UFS suspend patches |
| `SUSPEND_DEEP` | `1` | Cmdline `mem_sleep_default=deep` + install systemd sleep config |

Disable either for A/B testing:

```bash
SUSPEND_DEEP=0 ./make.sh              # kernel patches only, no cmdline/userspace
SUSPEND_DEEP_PATCHES=0 ./make.sh      # skip UFS suspend patches entirely
```

## After `sudo ./update.sh`

- Kernel cmdline includes `mem_sleep_default=deep` and `ufshcd_core.uic_cmd_timeout=3000`
- `/etc/systemd/sleep.conf.d/masi-deep-suspend.conf` → `SuspendState=mem`
- `/etc/systemd/logind.conf.d/masi-suspend.conf` → power button suspends

Reboot, then verify:

```bash
cat /sys/power/mem_sleep
# expect: s2idle [deep]  (deep selected when mem_sleep_default=deep)

systemctl suspend
# or short test:
sudo rtcwake -m mem -s 30
```

After resume:

```bash
dmesg | grep -iE 'ufs|ufshcd|suspend|resume' | tail -30
mount | grep ' / '
touch /tmp/suspend-test && rm /tmp/suspend-test
```

**Expected:** root stays read-write; one UFS host reset per deep resume is normal (`LINK_OFF`).

## Troubleshooting

### Instant wake (< 1 s)

- Thor: patch 1013 reduces TSENS uplow wake storms
- Check `cat /proc/acpi/wakeup` and `dmesg` for wake sources

### Storage read-only after resume

- Confirm patches applied: `dmesg | grep ufshcd_relinking` won't show — instead check build log for `Verify MaSi deep-suspend stack` OK
- Rebuild clean: `rm -rf .cache/linux-* output/.build` then `./make.sh`

### Fetch patches manually

```bash
python3 scripts/fetch-rocknix-suspend-patches.py
# or
./scripts/fetch-rocknix-suspend-patches.sh
```

Only missing files are downloaded. Use `--force` to replace vendored copies (not recommended for `1011` unless you re-port for linux-7.0).

**Build tip:** if MaSi suspend patches fail after a partial build, remove the kernel tree stamp and rebuild:

```bash
rm -rf output/.build/linux-* .cache/linux-*
./make.sh
```

MaSi applies suspend patches in dependency order: `1006` → `1007` → `1008` → **`1011`** → `1009` → `1010` → `1012` → `1013`.

## Userspace note (Armbian vs ROCKNIX)

ROCKNIX also ships `030-suspend_mode` for `/storage/.config`. MaSi installs equivalent **systemd** snippets under `/etc/` during `update.sh`. KDE/Gnome power settings may still need “Sleep when pressing power button” if a desktop overrides logind.

## Status

Experimental — PR still open upstream. Report device + `dmesg` if suspend fails on Odin2/Mini/Portal (Thor has the most testing).
