# DTB inventory — ROCKNIX multidevice chain

Reference analysis (`rocknix-boot-partition/KERNEL`, ROCKNIX 7.0.11).  
MaSi-OS builds integrate its own DTBs; ROCKNIX is only used to validate order and checksums.

## ABL zImage format

```
zImage = gzip(Image) + chain of 11 concatenated DTBs
```

ABL picks the DTB by hardware (multidevice without reflashing ABL).

## 11 detected slots

| Slot | Size | Device / hint |
|------|------|---------------|
| 00 | 176793 | `qcom,qcs8550` |
| 01 | 176534 | `qcom,qcs8550` |
| 02 | 178818 | `qcom,qcs8550` |
| 03 | 176223 | `qcom,qcs8550` |
| 04 | 177169 | generic base |
| 05 | 188388 | `ayn,odin2` |
| 06 | 186404 | `ayn,odin2mini` |
| 07 | 189886 | `ayn,odin2portal` |
| 08 | 192261 | `ayn,thor` |
| 09 | 191012 | `retroidpocket,rp6` |
| 10 | 190962 | `retroidpocket,rp6` (variant) |

Slots 0–4: Qualcomm base DTBs. Slots 5–10: AYN / Retroid profiles.

## Commands

```bash
./scripts/vendor-dtb-chain.sh /path/to/ROCKNIX/KERNEL   # once
./make.sh   # generates .build/.../zImage with 11 DTBs
```

Slot map: `config/dtb-chain.map`  
ABL boot (not EFI): [DTB-ABL.md](DTB-ABL.md)
