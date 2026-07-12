# Display boot — blue screen / black screen (SM8550 ABL)

## Updater inputs (from your running system only)

| Input | Source |
|-------|--------|
| `root=UUID=` | `/boot/LinuxLoader.cfg` → else `/boot/KERNEL` |
| Everything else | Built/downloaded from public sources (see README) |

`LinuxLoader.cfg` is **not** used at boot on EFI/ABL systems — only read when packing `boot/KERNEL`.

## Build

```bash
./make.sh
sudo ./update.sh
```

Default cmdline matches LinuxLoader 6.18.8. Optional: `ABL_CMDLINE_EXTRAS=1`.

## LinuxLoader

`DisableDisplayHW = true` — `./scripts/setup-linuxloader-cfg.sh`

## Black screen on Odin 2 Mini (boot stops before Linux)

Boot is **EFI / ABL → `boot/KERNEL`** only (single Android bootimg). `LinuxLoader.cfg` is **not** used at boot — only as a source for `root=UUID=` when packing `KERNEL`.

1. **ROCKNIX-ABL → Set the Device → Odin 2 Mini** (not Odin 2). All AYN units share `qcom,board-id`; ABL uses the stored device name to pick a slot in the embedded DTB chain.
2. Rebuild with current `config/dtb-chain.map` (no `aim300`; standard ROCKNIX slot order).
3. On **each** device: `sudo ./update.sh` so `KERNEL` gets that SD’s `root=UUID=` (see [MULTI-DEVICE-DIST.md](MULTI-DEVICE-DIST.md)).
4. After boot: `tr -d '\0' < /proc/device-tree/model` must show `AYN Odin 2 Mini`.

See [DTB-ABL.md](DTB-ABL.md).
