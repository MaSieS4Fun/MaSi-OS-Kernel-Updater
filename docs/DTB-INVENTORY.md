# DTB inventory — ABL multidevice chain

MaSi-OS builds all 11 chain slots from **public kernel sources** (no extract from other Linux images).

## ABL zImage format

```
zImage = gzip(Image) + chain of 11 concatenated DTBs
```

ABL + stored device setting pick the correct DTB.

## Slot map (see `config/dtb-chain.map`)

| Slot | kbuild DTB | Hint |
|------|------------|------|
| 00, 05 | `qcs8550-ayn-odin2.dtb` | `ayn,odin2` |
| 01, 06, 10 | `qcs8550-ayn-odin2mini.dtb` | `ayn,odin2mini` |
| 02, 07 | `qcs8550-ayn-odin2portal.dtb` | `ayn,odin2portal` |
| 03, 08 | `qcs8550-ayn-thor.dtb` | `ayn,thor` |
| 04, 09 | `qcs8550-retroidpocket-rp6.dtb` | `retroidpocket,rp6` |

**Not used:** `qcs8550-aim300-aiot.dtb` (generic reference board — causes wrong DTB on AYN handhelds).

RP6 DTS: `patches/masi/` (from public LineageOS kernel-ack, adapted for Armbian).

See [DTB-ABL.md](DTB-ABL.md).
