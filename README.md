# Linux on the Samsung Galaxy S20 FE 5G (`r8q`)

Mainline Linux + **Arch Linux ARM** on the Samsung Galaxy S20 FE 5G Snapdragon
(codename **`r8q`**, SoC **SM8250 "kona" / Snapdragon 865**), booted through
**[Mu-Silicium](https://github.com/Project-Silicium/Mu-Silicium) UEFI** — not a
downstream Android kernel, the **real mainline kernel**.

Everything here exists so that **anyone with their own r8q** can reproduce it
from clean upstream sources: the device-tree change that lights the panel, the
kernel config, the switch-root initramfs, the systemd services, and a small set
of scripts that take you from a UEFI flash to a booting Arch install you can SSH
into.

> **Read [`PREREQUISITES.md`](PREREQUISITES.md) first** (unlocked bootloader,
> host packages, and the fact that this **wipes your userdata**), then follow
> **[`INSTALLATION.md`](INSTALLATION.md)**. The quickest way is its §0: a
> bootable installer image (Releases) you run from a microSD card.

> **No proprietary firmware is shipped.** Storage, USB and display run on
> built-in mainline drivers with no firmware at all. GPU acceleration needs the
> Adreno 650 firmware from **linux-firmware** (`a650_sqe.fw`, `a650_gmu.bin`)
> plus the **Samsung-signed zap shader from your own device's stock firmware**
> (Samsung's TrustZone only accepts Samsung's signature) — see
> [`INSTALLATION.md` §9](INSTALLATION.md).

---

## What works today

| # | Milestone | State |
|---|-----------|-------|
| 1 | Mainline kernel boots — BusyBox/switch-root initramfs, output on the phone screen | ✅ |
| 2 | **UFS storage** — all LUNs and the full GPT show up as `/dev/sd*` (first try, no hacks) | ✅ |
| 3 | **Display** — mainline `msm` (DPU + DSI) with our own S6E3FC3 panel driver: **120 Hz**, hardware brightness, real screen-off | ✅ |
| 4 | **Arch Linux ARM + systemd** on userdata, root autologin on the panel (`tty1`) | ✅ |
| 5 | **SSH over USB** — `ssh root@172.16.42.1`, plus **USB tethering** (internet + `pacman`) | ✅ |
| 6 | **GPU acceleration** — Adreno 650 via freedreno/turnip (GLES 3.2 + Vulkan 1.3) | ✅ |
| 7 | **GNOME 50** on the panel — gdm autologin, mutter rendering on the Adreno (sway still available as a fallback) | ✅ |
| 8 | **Touchscreen** — STM FTS5CU56A multitouch, working under Plasma Mobile and GNOME; the Zinitix ZT7650 variant works too | ✅ |
| 9 | **Faster boot** — console `loglevel=3` (dropped `ignore_loglevel`) + a printk sysctl the initramfs can't override; ~12 s to userspace | ✅ |
| 10 | **Volume-Up key** — remapped to `pm8150l_gpios` gpio3, emits `KEY_VOLUMEUP` | ✅ |
| 11 | **Battery** — MAX77705 fuel gauge (`max17042`) telemetry **+ charging** (`max77705` MFD + charger); input current set from the detected USB port type (1.5 A wall charger, 700 mA PC) | ✅ |
| 12 | **Wi-Fi** — QCA6390 over PCIe via `ath11k_pci` + MHI; `wlp1s0` scans and associates | ✅ |
| 13 | **KDE Plasma Mobile** — `sddm` autologin → mobile shell on the Adreno, ~12 s cold boot (GNOME still installed as a fallback) | ✅ |
| 14 | **Camera** — rear telephoto (SK hynix Hi-847) through CAMSS and libcamera's software ISP, in plasma-camera; the other three cameras and autofocus are not done | ✅ |
| 15 | **microSD card** — up to 100 MHz (UHS SDR104, capped); a card inserted or removed while running is picked up within a second | ✅ |
| 16 | **CPU wedge** — every so often one core stops executing and takes the phone down with it. Localised (any core, A55 or A77; it stops in the cpuidle governor, before WFI) but **not fixed**; disabling the deep idle state only makes it rarer | ⚠️ open — see [`INSTALLATION.md` §11](INSTALLATION.md) |

See the [**Roadmap**](#roadmap) below for what's next (Bluetooth, USB host mode,
audio, a greeter/lock screen).

Mu-Silicium is
flashed to `BOOT`; the ESP is the `cache` partition reformatted vfat (`R8QESP`);
the rootfs is the `userdata` partition; the kernel is mainline **Linux 7.1.2**.

---

## Repository layout

```
r8q-arch/
├── README.md                     ← you are here
├── PREREQUISITES.md              ← read first (bootloader, host packages, data wipe)
├── INSTALLATION.md               ← the step-by-step
├── dts/                          ← display, touchscreen, battery and QCA6390 Wi-Fi nodes (sm8250-samsung-common.dtsi + r8q.dts)
├── patches/                      ← kernel patches (GPU zap shader; i2c FIFO force; touch; battery/USB-C; camera; display + panel driver)
├── config/                       ← r8q_bringup.config, cmdline.txt
├── initramfs/                    ← switch-root /init (+ irfs.devnodes)
├── rootfs/                       ← systemd services, networkd, Plasma Mobile/sddm wiring, cpuidle workaround, gadget script, GPU + touch + battery + Wi-Fi services
└── scripts/                      ← build-uefi / flash / deploy-esp / install-arch / host-tether / build_kernel
```

## Roadmap

The device boots to an accelerated KDE Plasma Mobile session you can touch and
SSH into. What's left, roughly in the order it's worth doing:

| Goal | What it needs | Notes |
|------|---------------|-------|
| **Bluetooth** | QCA6390 BT (`hci_qca` over UART/serdev) | Same chip as Wi-Fi, and the `qca6390-pmu` in the DT already drives its BT_EN line — so the power sequencing is done and this is the cheapest remaining win. |
| **USB host mode** | dwc3 role switch + VBUS (`pm8150b` regulator or powered OTG hub) | Currently peripheral-only (that's how SSH works). Host mode gets a real keyboard/mouse. Needs a role-switch path and VBUS supply. |
| **Greeter / lock screen** | Replace sddm autologin with a real login | Plasma Mobile already ships `plasma-keyboard` as an on-screen keyboard, so a headless login is now viable. Pure userspace/config work; no kernel changes. |
| **Audio** | LPASS + WCD938x codec + `cs35l41` speaker amps (SoundWire) | The hardest mainline bring-up here; lowest priority for a dev device. |

## The short version of how it boots

Download mode → `heimdall` flashes **Mu-Silicium UEFI** (with our DTB embedded)
to `BOOT` → UEFI auto-runs `\EFI\BOOT\BOOTAA64.EFI` (our kernel `Image`, EFI-stub,
with an embedded **switch-root initramfs**) → the initramfs mounts `userdata` and
`switch_root`s into **Arch Linux ARM / systemd** → NCM USB gadget comes up →
`ssh root@172.16.42.1`.

The kernel `Image` and the device tree both live on the **ESP**. The forced
command line carries `dtb=r8q.dtb`, so the EFI stub loads `\r8q.dtb` from the ESP
root instead of the copy embedded in the firmware — and it **refuses to boot if
that file is missing**; there is no fallback. Both files are swapped over
mass-storage mode, or straight from the running phone, which can mount its own
ESP. Neither a kernel nor a device-tree change needs a re-flash.

## Hardware notes

The short version of what each part needs. The details are in
[`INSTALLATION.md`](INSTALLATION.md) and in the comments of the files named here.

- **GPU** — `msm` is loaded after boot with `separate_gpu_kms=1`: the Adreno is
  its own render node (`renderD128`), the display its own card. It needs the
  **Samsung-signed zap shader from your own phone**, loaded into dynamically
  allocated memory instead of the DT carveout (`msm.r8q_zap_dyn=1`,
  `patches/0001`–`0002`). `r8q-gpu.service` loads `msm` once — never unload it —
  and the display manager must start after it, or the session silently runs on
  the CPU. See INSTALLATION §9 and §12.
- **Touchscreen** — STM FTS5CU56A on `i2c5`, with its own small driver
  (`patches/fts5cu56a.c`) and `i2c-qcom-geni.r8q_force_fifo=1` (`patches/0003`)
  to make the bus usable. Some units carry a Zinitix ZT7650 instead;
  `patches/0007` adds it to the mainline `zinitix` driver, and one DTB covers
  both. `r8q-touch.service` loads whichever is fitted.
- **Display & power** — the panel is a Samsung S6E3FC3 (command mode, DSC);
  `patches/0012` drives it through mainline `msm` at 120 Hz with DCS
  brightness. `patches/0010` keeps the boot console alive until `msm` takes
  over, `patches/0011` stops msm reprogramming the DSI PLL on every panel
  command (that corrupted frames). Check your panel first, and stage three
  extra modules — INSTALLATION §13. **Suspend is disabled on purpose**: s2idle
  hard-resets this SoC.
- **Battery** — MAX77705 on `i2c0`: fuel gauge through mainline
  `max17042_battery`, charging through the `max77705` MFD + charger
  (`patches/0005` accepts the PASS2 revision this phone has). `patches/0009`
  adds a driver for its USB-C block: it routes the USB data lines to the SoC
  (no cable replug after a reboot) and sets the charger's input limit from the
  detected port type (1.5 A on a wall charger, 700 mA on a PC).
- **Wi-Fi** — QCA6390 on PCIe via `ath11k_pci` + MHI, firmware from
  `linux-firmware`. `r8q-wifi.service` loads the stack in order. Two modules are
  easy to miss, and Wi-Fi fails silently without them: `phy-qcom-qmp-pcie` and
  `qrtr-mhi`. NetworkManager owns Wi-Fi and must leave `usb0` (the SSH link)
  alone. The MAC address is random on every boot. See INSTALLATION §10.
