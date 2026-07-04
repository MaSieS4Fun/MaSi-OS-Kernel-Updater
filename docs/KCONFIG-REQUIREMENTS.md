# `.config` requirements for gaming performance

## Is it only `CONFIG_SCHED_SMT`?

**No.** The ~40–50% regression comes from the **full compiled kernel profile**.

| Option | Good kernel (6.18.8 ref.) | ROCKNIX 7.0.11 stock | Fix without recompile? |
|--------|---------------------------|----------------------|------------------------|
| `CONFIG_SCHED_SMT` | `y` | not set | **No** |
| `CONFIG_PSI` | off | `y` | Partial: `psi=0` |
| `CONFIG_MMC_SDHCI_MSM_DOWNSTREAM` | `y` | missing | **No** |
| `CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE` | `y` | `y` | Userspace helps |
| `CONFIG_DRM_LONTIUM_LT8912B` | off / `m` | `y` built-in | **No** |
| EAS capacities (Armbian patches) | A510=326 | may vary | **No** |

### Implications

1. A clean initrd improves boot and errors — it does **not** replace a misconfigured scheduler/I/O stack.
2. Userspace services (governors) mitigate load with peripherals — they do **not** enable `SCHED_SMT`.
3. **Recompiling with `config/golden.config`** is the path to match the gaming reference.

Overview: [GAMING-PERFORMANCE.md](GAMING-PERFORMANCE.md)

## MaSi-OS profile

`config/golden.config` — vendored starting point (ayn-sm8550-kernel / verified 6.18.8 profile):

```
CONFIG_SCHED_SMT=y
# CONFIG_PSI is not set
CONFIG_MMC_SDHCI_MSM_DOWNSTREAM=y
# CONFIG_DRM_LONTIUM_LT8912B is not set
CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y
```

Maintained and adjusted **only in this repo**.
