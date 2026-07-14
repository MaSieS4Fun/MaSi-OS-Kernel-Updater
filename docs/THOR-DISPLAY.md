# AYN Thor — displays and touch

## Bottom AMOLED (CH13726A, DSI-1) — black panel

### Symptom

- Driver probes without errors, DSI PLL locks, DCS writes “succeed”
- `dpu_encoder_frame_done_timeout` in dmesg
- Panel stays black; bottom touch may work (power is OK)

### Root cause

The Armbian downstream driver `panel-ddic-ch13726a.c` had **inverted reset GPIO polarity** vs mainline `panel-chipwealth-ch13726a.c`.

With `reset-gpios = <&tlmm 133 GPIO_ACTIVE_LOW>` in the Thor DTB:

| Driver state | Downstream (broken) | Mainline (correct) |
|--------------|---------------------|---------------------|
| Probe default | `GPIOD_OUT_LOW` | `GPIOD_OUT_HIGH` |
| End of `reset()` pulse | logical **1** → panel **held in reset** | logical **0** → panel **released** |
| `unprepare()` / error | logical 0 (release) | logical 1 (assert reset) |

The panel never left hardware reset during normal “on”, so all DCS traffic was fire-and-forget into a dead chip.

### Fix (MaSi)

Patch `patches/masi/1005-thor-ch13726a-reset-polarity-fix.patch` aligns the downstream driver with mainline reset semantics. **No DT change** — `GPIO_ACTIVE_LOW` on GPIO133 is correct.

After rebuild + `sudo ./update.sh` on Thor:

- Bottom panel should light up
- `frame_done_timeout` should disappear
- Bottom touch orientation fixes itself (was a symptom of the dead panel)

### Verify after boot

```bash
tr -d '\0' < /proc/device-tree/model
dmesg | grep -iE 'ch13726|frame_done|dsi0'
```

---

## Top / main panel touch — ~90° rotation (KDE)

The main Thor panel is mounted rotated (`rotation = <90>` in DT). KDE applies touch mapping from **output rotation**, not panel DT alone.

**Fix (userspace, no kernel rebuild):**

1. KDE → **System Settings → Display**
2. Select the main (top) output
3. Set rotation to **Right (270°)**

On Thor this mainly adjusts **touch orientation**; the image may already look upright. On Wayland the setting is stored in `kwinoutputconfig.json` and persists across sessions.

---

## ABL

ROCKNIX-ABL → **Set the Device → AYN Thor** (slot 4 in `config/dtb-chain.map`).
