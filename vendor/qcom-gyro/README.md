# vendor/qcom-gyro

## Used by this kernel build

- `firmware-thor-adsp/` — overlay ADSP Thor (SH5001 split `.mdt`) via `lib/gyro-firmware.sh` into `output/.../firmware/`.

## Not staged by `./make.sh`

- `share-qcom/` and `src/` — leftovers from the old in-tree userspace bundle (`fix-ayn-gyro`).  
  Live install path: **`~/Projects/giroscopio`**.

Kernel gyro pieces (DT FastRPC / SensorsPD / `CONFIG_UHID`) live under `patches/masi/` and `config/golden.config`. See `docs/GYRO.md`.
