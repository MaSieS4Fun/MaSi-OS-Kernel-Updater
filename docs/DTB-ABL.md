# ABL multidevice boot — DTB selection

## How ABL works

The **ABL** reads `boot/KERNEL`, decompresses `gzip(Image)` + **concatenated DTB chain**, and picks **`chain[device_index]`** using the model stored in ROCKNIX-ABL (“Set the Device”).

Do **not** use `devicetree=` / `dtb=` in cmdline.

## Reference Slot Order

Extracted from `armada-boot-partition/KERNEL` (works on all SM8550 units):

| Slot | Device |
|------|--------|
| 0 | (Odin 3 / other SoC — index padding) |
| **1** | **Odin 2 Portal** |
| **2** | **Odin 2** |
| **3** | **Odin 2 Mini** |
| **4** | **Thor** |
| **5 / 6** | **Retroid Pocket 6** |
| 7–8 | other handheld refs |
| 9–12 | `qcom,qcs8550` generic fallbacks |

MaSi previously used `0=Odin2, 1=Mini, 2=Portal…` — **wrong index map**. ABL index 2 (Odin 2) received Portal’s DTB, index 3 (Mini) received Thor’s DTB, etc.

Editable map: `config/dtb-chain.map` (14 slots, reference-aligned).

```bash
./scripts/extract-armada-dtb-chain.sh   # refresh reference/armada-dtb-chain/
```

## ABL: set the correct device

1. Hold **Volume Down** at power-on → ABL menu  
2. **Set the Device** → exact model  
3. **Boot Mode** = Linux → **START**

## Verification

```bash
./make.sh
# log should show slot-01=portal, slot-02=odin2, slot-03=mini …

tr -d '\0' < /proc/device-tree/model   # after boot
```

See also [MULTI-DEVICE-DIST.md](MULTI-DEVICE-DIST.md) (UUID / initrd).
