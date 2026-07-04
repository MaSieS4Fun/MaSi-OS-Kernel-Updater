# Documentation

| Document | Description |
|----------|-------------|
| [GAMING-PERFORMANCE.md](GAMING-PERFORMANCE.md) | **Start here** — standard vs performance tuning on SM8550; golden config, initrd, and build reference at the end |
| [KCONFIG-REQUIREMENTS.md](KCONFIG-REQUIREMENTS.md) | Kernel `.config` checklist for gaming |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Build pipeline and output layout |
| [DTB-ABL.md](DTB-ABL.md) | ABL multidevice boot and DTB chain |
| [DTB-INVENTORY.md](DTB-INVENTORY.md) | 11-slot DTB reference (ROCKNIX order) |
| [PROJECTS.md](PROJECTS.md) | How this repo relates to other SM8550 kernel work |
| [GITHUB-SETUP.md](GITHUB-SETUP.md) | Publish or update this project on GitHub |

## Quick paths

- Build: `./make.sh`
- Install: `sudo ./update.sh`
- Vendor DTB chain (once): `./scripts/vendor-dtb-chain.sh /path/to/ROCKNIX/KERNEL`
- Performance reference: last section of [GAMING-PERFORMANCE.md](GAMING-PERFORMANCE.md)
