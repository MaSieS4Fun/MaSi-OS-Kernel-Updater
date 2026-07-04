# ABL multidevice boot — DTB selection

## How ROCKNIX / ABL works

The **ABL** bootloader (not GRUB/EFI) reads `boot/KERNEL` and:

1. Decompresses the kernel slot → `gzip(Image)` + **concatenated DTB chain**
2. **Picks the DTB** based on detected hardware (Odin2, Mini, Portal, Thor, RP6…)
3. Boots the kernel with that device tree

You do **not** need — and must **not** use — `devicetree=` / `dtb=` in cmdline or `grub.cfg` for this flow.

## MaSi-OS zImage layout

```
zImage = gzip(gaming Image) + slot-00.dtb + … + slot-10.dtb
```

| Slots | Source | Device |
|-------|--------|--------|
| 0–4 | reference (Qualcomm base) | ABL placeholders |
| 5 | kbuild overlay | Odin 2 |
| 6 | kbuild overlay | Odin 2 Mini |
| 7 | kbuild overlay | Odin 2 Portal |
| 8 | kbuild overlay | Thor |
| 9–10 | reference | Retroid Pocket 6 |

Editable map: `config/dtb-chain.map`

## Reference chain

Preference order:

1. `device-tree/vendored/slot-*.dtb` — local vendored copy (recommended)
2. `.cache/dtb-chain/reference/` — extraction cache
3. Extract from `ROCKNIX_KERNEL` (analysis / first time only)

Vendor once (any ROCKNIX SM8550 `KERNEL` bootimg file):

```bash
./scripts/vendor-dtb-chain.sh /path/to/ROCKNIX/KERNEL
# or:
ROCKNIX_KERNEL=/path/to/KERNEL ./scripts/vendor-dtb-chain.sh
```

## Verification

After `./make.sh`:

```bash
# In build output:
ls output/*-masi/.staging/zImage
ls output/*-masi/.staging/dtb-chain/

# After boot on ABL device:
tr -d '\0' < /proc/device-tree/model
tr -d '\0' < /proc/device-tree/compatible | tr '\0' ' '
```

If the Mini boots with an Odin2 DTB, ABL did not find the correct slot — check chain order.

## EFI vs ABL

| Mode | Who picks DTB |
|------|---------------|
| **ABL / ROCKNIX bootimg** (this project) | ABL, embedded chain |
| EFI/GRUB + `devicetree=` | GRUB — **not used here** |

MaSi-OS bootimg cmdline does **not** include `devicetree=`.
