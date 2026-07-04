# MaSi-OS Kernel Updater

Build and install a **performance-tuned** Linux kernel for Qualcomm **SM8550** handhelds (AYN Odin 2, Mini, Portal, Thor, Retroid Pocket 6, …) on **Armbian**, packaged as an ABL **`boot/KERNEL`** bootimg — same format used by ROCKNIX multidevice images.

Repository: **https://github.com/MaSieS4Fun/MaSi-OS-Kernel-Updater**

---

## Features

- Recompiles kernel with **`config/golden.config`** (gaming scheduler, storage, PSI off)
- **11-DTB ABL chain** — one `KERNEL` bootimg for multiple devices
- **Gaming cmdline** — no `irqaffinity=0-2`; `psi=0`
- Small **gold initrd** (~47 MB) that fits ABL size limits
- **`update.sh`** — backup, clean install to `/boot`, firmware, modules, optional reboot

---

## Supported devices

| Device | Notes |
|--------|--------|
| AYN Odin 2 / Mini / Portal / Thor | kbuild DTBs in slots 5–8 |
| Retroid Pocket 6 | reference DTBs in slots 9–10 |
| Other SM8550 ABL handhelds | same bootimg format if DTB chain matches |

ABL picks the DTB automatically — do **not** use `devicetree=` in cmdline.

---

## Quick start

### Fresh clone on your handheld (Armbian SM8550)

Works on **any** supported device if you already boot Armbian with an ABL `KERNEL` on `/boot`:

```bash
git clone https://github.com/MaSieS4Fun/MaSi-OS-Kernel-Updater.git
cd MaSi-OS-Kernel-Updater

sudo apt install build-essential libssl-dev libncurses-dev libelf-dev \
  flex bison bc curl patch initramfs-tools abootimg python3 u-boot-tools git

./scripts/first-run.sh    # optional — caches DTB + initrd from /boot
./make.sh
sudo ./update.sh
```

**Automatic on first build (no extra steps required on device):**

| Need | Source on your handheld |
|------|-------------------------|
| `root=UUID=` for cmdline | `/boot/LinuxLoader.cfg` if present, else `/boot/KERNEL` |
| DTB chain slots 0–4, 9–10 | Extracted from `/boot/KERNEL` |
| Initrd gold | `/boot/initrd.img-*` copied to `reference/` |
| Initrd fallback | Small `efi-clean` initrd (no firmware inside) |
| Firmware in output | Copied from `/usr/lib/firmware` on host |

**One-time manual step** only if you build **off-device** (PC without `/boot/KERNEL`):

```bash
./scripts/vendor-dtb-chain.sh /path/to/any/SM8550/KERNEL
./scripts/setup-reference-initrd.sh /path/to/initrd.img
```

Check before build: `./lib/preflight.sh`

### Requirements

Build on the handheld or an Armbian SM8550 chroot:

```bash
sudo apt install build-essential libssl-dev libncurses-dev libelf-dev \
  flex bison bc curl patch initramfs-tools abootimg python3 u-boot-tools git
```

You need an existing **`/boot/KERNEL`** on the build device (normal on Armbian ABL installs).

### Build (after requirements)

```bash
./make.sh                              # interactive version menu
KERNEL_VER=7.0.14 ./make.sh            # non-interactive
KERNEL_VER=7.0.14 BUILD_COMPILE=0 ./make.sh   # repack only (no recompile)
```

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
| `BUILD_COMPILE` | `1` | `0` = repack only |

---

## Documentation

| Doc | Topic |
|-----|--------|
| [GAMING-PERFORMANCE.md](docs/GAMING-PERFORMANCE.md) | Standard vs performance; golden config & initrd reference |
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
