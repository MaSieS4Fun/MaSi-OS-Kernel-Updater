# Related projects

**MaSi-OS Kernel Updater** (this repo) is self-contained: it does not import other projects' build scripts at runtime.

## This repo — MaSi-OS Kernel Updater

- Compiles Linux edge SM8550 with `config/golden.config`
- Generates initramfs (`gold` / `efi-clean`)
- Packages `boot/KERNEL` with an 11-DTB multidevice chain
- Installs via `update.sh`
- Goal: **performance-tuned** kernel on Armbian with ABL boot

## Repack-only ports (different goal)

Some community projects **do not recompile** — they extract a vendor zImage + DTBs and swap initrd/cmdline. That is faster but keeps the vendor kernel `.config` (often standard, not performance).

Useful for comparison or when recompiling is not an option. Not a substitute for the performance profile described in [GAMING-PERFORMANCE.md](GAMING-PERFORMANCE.md).

## Optional references (not required at runtime)

| Resource | Use |
|----------|-----|
| ROCKNIX SM8550 `KERNEL` file | One-time `vendor-dtb-chain.sh` for DTB slots 0–4 and 9–10 |
| Reference EFI initrd | Optional `GOLD_INITRD_REF` for `INITRAMFS_PROFILE=gold` |
| Armbian SM8550 images | Build host / rootfs with firmware for `output/firmware/` |

You do **not** need sibling repos on disk — only files or paths you point to with env vars.

## Recommended flow for users

| Goal | Approach |
|------|----------|
| Gaming performance on Armbian + ABL | **This repo** — build + `update.sh` |
| Quick test with stock vendor kernel | Repack port (any project that embeds vendor zImage) |
| Understand standard vs performance | [GAMING-PERFORMANCE.md](GAMING-PERFORMANCE.md) |
