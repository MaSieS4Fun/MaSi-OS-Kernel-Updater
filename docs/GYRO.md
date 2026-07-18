# AYN Thor / Odin 2 — giroscopio (capa kernel)

El Thor (SH5001) y el Odin 2 (LSM6DSV) exponen acelerómetro y giroscopio vía **Qualcomm Sensor Core** en el ADSP. Este repo solo entrega la **capa kernel + firmware** necesaria. El userspace (DSU, DualSense UHID, Steam Game Mode) vive en el proyecto externo **`giroscopio`**.

## Qué va en el kernel vs. fuera

| Capa | Dónde | Qué |
|------|-------|-----|
| **Kernel/DTB** | `boot/KERNEL` (`./make.sh`) | FastRPC SensorsPD, routing PDR, DT gyro, `CONFIG_UHID=y` |
| **Firmware** | `firmware/qcom/sm8550/ayn/thor/` | ADSP split `.mdt` (Thor SH5001); Odin 2 `adsp.mbn` intacto |
| **Userspace** | **no se genera aquí** | Proyecto `~/Projects/giroscopio` → `./install.sh` |

`update.sh` **solo instala kernel + firmware + modules**. Tras reboot:

```bash
sudo ./update.sh
sudo reboot
# userspace (stack sensores + motion + sdl-pad + Steam):
cd ~/Projects/giroscopio && ./install.sh
```

## Parches / overlays en este árbol

- `patches/masi/1025-misc-fastrpc-adsp-sensor-pd-and-legacy-ioctl.patch`
- `patches/masi/1026-dt-bindings-misc-qcom-fastrpc-pd-routing.patch`
- `patches/masi/qcs8550-ayn-gyro-fastrpc.dtsi.frag` — remote heap + SensorsPD (todos los AYN SM8550)
- `patches/masi/qcs8550-ayn-thor-gyro-fastrpc-pd.dtsi.frag` — `qcom,pd-type` solo en Thor
- `lib/gyro-firmware.sh` — overlay ADSP Thor en `firmware/`
- `vendor/qcom-gyro/firmware-thor-adsp/` — blobs ADSP Thor
- `config/golden.config` — `CONFIG_UHID=y` (necesario para el DualSense virtual del userspace)

## Thor vs Odin 2

| Dispositivo | IMU | Nota DT |
|-------------|-----|---------|
| **Thor** | Senodia SH5001 | `qcom,pd-type` en FastRPC |
| **Odin 2** | ST LSM6DSV | sin forzar pd-type (bancos first-free) |

## Userspace (giroscopio)

No uses el antiguo `fix-ayn-gyro/` de este repo (eliminado). Un solo instalador:

```bash
cd ~/Projects/giroscopio && ./install.sh
./install.sh --check
```

Incluye qrtr/hexagonrpcd/libssc, `qcom-motion` (DSU `:26760`), `qcom-sdl-pad`, mapeo SDL y wrapper Steam Game Mode. Detalle: `~/Projects/giroscopio/README.md`.

## Limitaciones conocidas (capa kernel)

- Odin 2 necesita la partición `persist` de Android para calibración de fábrica (lo consume el userspace).
- El stack espera la tarjeta ALSA del handheld antes de abrir FastRPC (comparte ADSP con audio).
- En el DT, **`qcom,pd-type` solo va en Thor**. Forzarlo en common impedía publicar SSC en Odin 2.
- Instalar Image + modules del **mismo** build (`./update.sh` completo). Un `make Image` solo puede dejar pantalla negra.
