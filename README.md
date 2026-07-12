# MaSi-OS Kernel Updater

Build and install a **performance-tuned** Linux kernel for Qualcomm **SM8550** handhelds (AYN Odin 2, Mini, Portal, Thor, Retroid Pocket 6, …) on **Armbian**, packaged as an ABL **`boot/KERNEL`** bootimg.

Repository: **https://github.com/MaSieS4Fun/MaSi-OS-Kernel-Updater**

---

## Features

- Recompiles kernel with **`config/golden.config`** (gaming scheduler, storage, PSI off)
- **11-DTB ABL chain** — all slots compiled from kernel source
- **Firmware** — downloaded from public Armbian firmware git
- **Initrd** — built locally (`efi-clean`); no copy from other images
- **Gaming cmdline** — matches working LinuxLoader 6.18.8 (no `video=efifb:off` by default)
- **Cmdline UUID** — from `/boot/LinuxLoader.cfg` or `/boot/KERNEL` on the system
- **Initrd** — built locally (`efi-clean`); optional `INITRAMFS_PROFILE=gold` uses `reference/` only
- **`update.sh`** — backup, clean install to `/boot`, firmware, modules, optional reboot

---

## Supported devices

| Device | Notes |
|--------|--------|
| AYN Odin 2 / Mini / Portal / Thor | slots 0–3 (+ alts); set **ABL → device model** |
| Retroid Pocket 6 | slots 4 / 9 (`patches/masi/`) |

In ROCKNIX-ABL: **Set the Device** to your exact model (Mini ≠ Odin 2). Do **not** use `devicetree=` in cmdline.

---

## Autonomous build (no other Linux image required)

| Component | Public source |
|-----------|----------------|
| Kernel | [kernel.org](https://kernel.org) CDN |
| Patches | [Armbian build](https://github.com/armbian/build) + `patches/masi/` (RP6 DTS) |
| DTBs | Compiled from kernel (`config/dtb-chain.map`) |
| Firmware | [armbian/firmware](https://github.com/armbian/firmware) git (`FIRMWARE_SOURCE=download`) |
| Initrd | Built with `mkinitramfs` (`INITRAMFS_PROFILE=efi-clean`) |
| Bootimg layout | `config/bootimg.abl.cfg` (in repo) |
| Root UUID | **`/boot/LinuxLoader.cfg`** or **`/boot/KERNEL`** on the system you update |

Fresh clone on a handheld with your preconfigured `/boot/`:

```bash
git clone https://github.com/MaSieS4Fun/MaSi-OS-Kernel-Updater.git
cd MaSi-OS-Kernel-Updater
sudo apt install build-essential libssl-dev libncurses-dev libelf-dev \
  flex bison bc curl patch initramfs-tools abootimg python3 u-boot-tools \
  git device-tree-compiler
./make.sh
sudo ./update.sh
```

No ROCKNIX, ARMADA, or ostree image needed for the build itself.

### Requirements

Build on the handheld or an Armbian SM8550 chroot:

```bash
sudo apt install build-essential libssl-dev libncurses-dev libelf-dev \
  flex bison bc curl patch initramfs-tools abootimg python3 u-boot-tools git
```

You need **`/boot/LinuxLoader.cfg`** or **`/boot/KERNEL`** on the device (for `root=UUID=` only — not for DTBs/firmware/initrd).

### Build (after requirements)

```bash
./make.sh                              # interactive version menu (only kernels with Armbian sm8550-* patches)
KERNEL_VER=7.0.14 ./make.sh            # non-interactive
KERNEL_VER=7.0.14 BUILD_COMPILE=0 ./make.sh   # repack only (no recompile)
```

**linux-7.1.x** appears in the menu only when Armbian publishes **`sm8550-7.1`** (no cross-series fallback to `sm8550-7.0`).

### Install

```bash
sudo ./update.sh
```

Backs up the running system to `output/old_kernel/` (owned by your user), then installs the new `boot/KERNEL`, firmware, and modules.

---

## Output layout

```
output/
├── <ver>-edge-sm8550-masi/          # install bundle
│   ├── boot/KERNEL
│   ├── firmware/
│   ├── modules/<release>/
│   ├── INSTALL.txt
│   └── MANIFEST.txt
├── .build/<ver>-edge-sm8550-masi/   # Image, zImage, initrd (intermediate)
├── meta/config-<release>            # kernel .config reference
└── old_kernel/                      # backup after update.sh
```

---

## Why not a stock / repacked kernel?

Standard SM8550 builds often lose **40–50% gaming FPS** once USB, Wi‑Fi, and audio are active. That is usually **standard vs performance tuning** (kernel options, cmdline, governors) — not “drivers are slow”.

Read: **[docs/GAMING-PERFORMANCE.md](docs/GAMING-PERFORMANCE.md)**  
Kernel checklist: **[docs/KCONFIG-REQUIREMENTS.md](docs/KCONFIG-REQUIREMENTS.md)**  
All docs: **[docs/README.md](docs/README.md)**

---

## Configuration

Defaults live in `config/defaults.conf`. Copy `config/defaults.conf.example` → `config/local.conf` for overrides (local.conf is gitignored).

| Variable | Default | Purpose |
|----------|---------|---------|
| `GAMING_TUNING` | `1` | Golden kconfig overrides |
| `INITRAMFS_PROFILE` | `gold` | Small initrd for ABL |
| `KERNEL_LOCALVERSION` | `-edge-sm8550` | Module directory name |
| `PATCH_POLICY` | `strict` | `tolerant` = ignore patch failures (not recommended) |
| `BUILD_COMPILE` | `1` | `0` = repack only |

---

## Documentation

| Doc | Topic |
|-----|--------|
| [GAMING-PERFORMANCE.md](docs/GAMING-PERFORMANCE.md) | Standard vs performance; golden config & initrd |
| [DISPLAY-BOOT.md](docs/DISPLAY-BOOT.md) | Blue/black screen, ROCKNIX ABL, UUID per device |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Build pipeline |
| [DTB-ABL.md](docs/DTB-ABL.md) | Multidevice ABL boot |
| [GITHUB-SETUP.md](docs/GITHUB-SETUP.md) | Publish or push updates to GitHub |
| [reference/README.md](reference/README.md) | Initrd gold profile setup |

---

## Related work

This repo **compiles** a gaming kernel. Other projects **repack** stock vendor zImages without recompiling — useful for comparison, different goal.

See [docs/PROJECTS.md](docs/PROJECTS.md).

---

## License

Scripts and documentation: [MIT](LICENSE).  
Built kernel, modules, and firmware: **GPL-2.0** and upstream licenses.
