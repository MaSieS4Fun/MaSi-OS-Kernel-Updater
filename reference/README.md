# Reference initrd (gold profile)

`INITRAMFS_PROFILE=gold` copies a **known-good** initrd (~47 MB, 0 kernel modules) into the build.  
Fresh clones do not include this file (too large for git).

## One-time setup (pick one)

**From your running Armbian system** (recommended):

```bash
./scripts/setup-reference-initrd.sh
```

**Manual copy:**

```bash
mkdir -p reference
cp /boot/initrd.img-7.0.14-edge-sm8550 reference/
# or any *-edge-sm8550 initrd from /boot/
```

**Custom path:**

```bash
GOLD_INITRD_REF=/path/to/initrd.img ./make.sh
```

The build checks, in order:

1. `GOLD_INITRD_REF` / `reference/initrd.img-<release>`
2. **`/boot/LinuxLoader.cfg`** → `initrd = "..."` under `/boot/`
3. Any `/boot/initrd.img-*` (cached to `reference/` when possible)
4. Initrd **extracted from `/boot/KERNEL`** bootimg

If gold is unavailable, the build falls back to a **minimal** mkinitramfs initrd (no firmware in initrd — firmware stays on rootfs).
