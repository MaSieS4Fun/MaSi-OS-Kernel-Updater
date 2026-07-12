# Architecture — MaSi-OS Kernel Updater

## Pipeline

```
kernel.org + Armbian sm8550 patches
        │
        ▼
config/golden.config (+ MaSi-OS overrides)
        │
        ▼
lib/kbuild.sh  →  Image, modules, DTBs
        │
        ├── lib/dtb-chain.sh     → zImage (gzip + 11 DTBs)
        ├── lib/initramfs.sh     → initrd (gold / efi-clean)
        └── lib/bootimg.sh       → output/boot/KERNEL

Build artifacts live under `output/.build/<release>-masi/`; kernel config reference under `output/meta/`.
The install bundle `<release>-masi/` holds only boot/, firmware/, modules/, and INSTALL.txt.
```

## Initramfs: `gold` and `efi-clean`

Own generation with `mkinitramfs` + hooks in `hooks/`, or copy of reference EFI initrd.

| Profile | Description |
|---------|-------------|
| `gold` (default) | Reference EFI initrd (~47 MB, 0 `.ko`, fits ABL bootimg) |
| `efi-clean` | Lightweight `mkinitramfs`, no early DRM, no unnecessary `.ko` |
| `minimal` | `MODULES=list` + no-early-drm hook (HDMI dock) |

Quality inspiration: small gold initrd (~47 MB, no `.ko` in cpio) — **without** extracting vendor blobs on every build.

## Phases

| Phase | Deliverable | Status |
|-------|-------------|--------|
| 0 | Docs, golden.config, analyze script | ✅ |
| 1 | `lib/kbuild.sh` — Image, modules, AYN DTBs | ✅ |
| 2 | `lib/dtb-chain.sh` — 11 DTBs + ABL zImage | ✅ |
| 3 | `lib/initramfs.sh` — initrd gold/efi-clean | ✅ |
| 4 | `lib/bootimg.sh` — boot/KERNEL (zImage+initrd, no devicetree=) | ✅ |
| 5 | `update.sh` — system install | ✅ |

## Bootimg cmdline

```
clk_ignore_unused pd_ignore_unused quiet rw rootwait root=UUID=<uuid>
```

UUID from `/boot/LinuxLoader.cfg` or `/boot/KERNEL`. Optional: `ABL_CMDLINE_EXTRAS=1`.

No `irqaffinity=0-2`, `fw_devlink.strict=1`, or **`devicetree=` / `dtb=`** (ABL picks the DTB).
