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
> **[`INSTALLATION.md`](INSTALLATION.md)**.

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
| 3 | **Display** — a *persistent, live* mainline framebuffer console on the AMOLED panel | ✅ |
| 4 | **Arch Linux ARM + systemd** on userdata, root autologin on the panel (`tty1`) | ✅ |
| 5 | **SSH over USB** — `ssh root@172.16.42.1`, plus **USB tethering** (internet + `pacman`) | ✅ |
| 6 | **GPU acceleration** — Adreno 650 via freedreno/turnip (GLES 3.2 + Vulkan 1.3) | ✅ |
| 7 | **GNOME 50** on the panel — gdm autologin, mutter rendering on the Adreno (sway still available as a fallback) | ✅ |
| 8 | **Touchscreen** — STM FTS5CU56A multitouch, working under Plasma Mobile and GNOME; the Zinitix ZT7650 variant works too | ✅ |
| 9 | **Faster boot** — console `loglevel=3` (dropped `ignore_loglevel`) + a printk sysctl the initramfs can't override; ~12 s to userspace | ✅ |
| 10 | **Volume-Up key** — remapped to `pm8150l_gpios` gpio3, emits `KEY_VOLUMEUP` | ✅ |
| 11 | **Battery** — MAX77705 fuel gauge (`max17042`) telemetry **+ charging** (`max77705` MFD + charger) | ✅ |
| 12 | **Wi-Fi** — QCA6390 over PCIe via `ath11k_pci` + MHI; `wlp1s0` scans and associates | ✅ |
| 13 | **KDE Plasma Mobile** — `sddm` autologin → mobile shell on the Adreno, ~12 s cold boot (GNOME still installed as a fallback) | ✅ |
| 14 | **CPU wedge root-caused** — the "phone dies under load" bug is `cpu7` never returning from `cpu-sleep-1-0` power collapse; that idle state is now disabled on cpus 4-7 | ✅ fix holding (first 50 min session clean; longer soak still welcome) |

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
├── dts/                          ← display fix, touchscreen, battery and QCA6390 Wi-Fi nodes (sm8250-samsung-common.dtsi + r8q.dts)
├── patches/                      ← kernel patches (GPU zap-shader; i2c FIFO force; FTS5CU56A touch driver)
├── config/                       ← r8q_bringup.config, cmdline.txt
├── initramfs/                    ← switch-root /init (+ irfs.devnodes)
├── rootfs/                       ← systemd services, networkd, Plasma Mobile/sddm wiring, cpuidle workaround, gadget script, GPU + touch + battery + Wi-Fi services
└── scripts/                      ← build-uefi / flash / deploy-esp / install-arch / host-tether / build_kernel
```

## The short version of how it boots

Download mode → `heimdall` flashes **Mu-Silicium UEFI** (with our DTB embedded)
to `BOOT` → UEFI auto-runs `\EFI\BOOT\BOOTAA64.EFI` (our kernel `Image`, EFI-stub,
with an embedded **switch-root initramfs**) → the initramfs mounts `userdata` and
`switch_root`s into **Arch Linux ARM / systemd** → NCM USB gadget comes up →
`ssh root@172.16.42.1`.

The DTB lives **inside the firmware** (Mu-Silicium exposes it as an EFI config
table via `DtPlatformDxe`), so DTB changes need a re-flash; the kernel `Image`
lives on the **ESP** and is swapped over mass-storage mode.

## How the GPU works (short version)

There is no mainline panel driver yet, so display and GPU are split: the panel
keeps scanning out of the firmware-lit `simple-framebuffer` (`card0`), while the
`msm` module is loaded post-boot with `separate_gpu_kms=1` and provides only the
Adreno 650 **render node** (`renderD128`). Compositors render on the GPU and
blit into the dumb buffer.

Two r8q-specific things make the GPU actually render (both in
[`patches/`](patches/)):
- Samsung's TrustZone rejects the generic zap shader from linux-firmware, and
  the GPU then stays locked in secure mode — every render write is silently
  dropped. You need the **Samsung-signed zap** from your own stock firmware.
- Loading that zap into the DT carveout hard-resets the SoC (Samsung's TZ
  rejects the region); the `msm.r8q_zap_dyn=1` patch loads it into dynamically
  allocated RAM instead, exactly like stock Android's `pil-tz-generic` does.

`rootfs/` ships the pieces: `r8q-gpu.service` (loads `msm` after boot — never
at coldplug, and **never unload it**), the modprobe options, and the desktop
wiring for whichever session you run. The drop-in ordering the display manager
after `r8q-gpu.service` matters either way: compositors choose their render
device once at startup, so if the display manager wins that race the whole
session silently runs on the CPU.

- **KDE Plasma Mobile (default)** — `sddm` autologin into `plasma-mobile.desktop`.
  KWin needs **no** GPU glue: it has a real split display/render-device concept,
  treats every `DRM_BUS_PLATFORM` node as compatible and prefers the one that
  isn't a software renderer, so it pairs `card0` (simpledrm) with `renderD128`
  (Adreno) by itself. It also derives scale **2.7** from the panel's DPI, which
  works only because the connector is DSI and the DT carries `width-mm`/`height-mm`.
- **GNOME (fallback, still installed)** — needs the `mutter-device-preferred-primary`
  udev tag so mutter renders on the Adreno and scans out on simpledrm, plus a gdm
  drop-in and gdm autologin. Switch back with
  `systemctl disable sddm && systemctl enable gdm`.
- A tty1 autologin profile that starts **sway** on the GPU is kept as a second fallback.

### The CPU wedge (`tmpfiles.d/50-r8q-cpuidle.conf`)

Until this was found, the phone would stop dead under sustained rendering. It is
not a display or GPU fault: **cpu7 enters the `cpu-sleep-1-0` power-collapse state
and never comes back out**, so every later `kick_all_cpus_sync()` — the BPF JIT's
text poking hits this constantly via systemd's cgroup BPF — blocks forever waiting
for a core that will not answer even an NMI. RCU says so directly, reporting cpu7
with an *even* dynticks counter (`idle=…/0x4000000000000000`), meaning it believes
that core is idle.

The tell is distinctive: **the kernel keeps answering ICMP while userspace stops
entirely** — ping stays at ~2 ms but `sshd` cannot emit its version banner. The
workaround disables idle `state1` on cpus 4-7 only; cpus 0-3 use a different state
and keep their power collapse. Same family as the s2idle hard reset — this SoC's
low-power paths are not trustworthy under mainline.

### Touchscreen

The STM **FTS5CU56A** touch controller sits on `i2c5` (`qupv3_se5`), powered by
a fixed LDO on **TLMM GPIO 92** that the firmware leaves off. No mainline driver
speaks its Samsung-TSP protocol, so `patches/fts5cu56a.c` is a small from-scratch
driver (device-ID handshake, system reset, the touchtype/scan-on command
sequence, and the 16-byte FIFO event format). Two quirks make the bus usable:
the SE5 GPI-DMA channels are TrustZone-owned and its FIFO writes hang, so
`patches/0003` adds `i2c-qcom-geni.r8q_force_fifo=1` (skip GPI, route data
through the SE-DMA path). `r8q-touch.service` loads the stack after boot.

r8q is **dual-sourced**: Samsung's overlay puts two touch controllers on i2c5 —
the STM part at 0x49 and a **Zinitix ZT7650 at 0x20** — and only the one that is
fitted answers. Both DT nodes stay enabled and each driver checks for its own
chip before registering anything, so a single DTB covers both variants (they
also share one interrupt line, so a driver binding to a chip that is not there
would take the IRQ from the one that should have it). Mainline's `zinitix`
driver only knows the older BT4xx/BT5xx generation, so `patches/0007` adds the
ZT7650: the vendor commands moved, the touch points moved from 0x0080 to 0x0200
and became one 16-byte event per contact with 12-bit packed coordinates, and
"point mode" is 0 rather than 2. `r8q-touch.service` only loads `zinitix.ko`
when the STM part did not bind. The ZT7650 path is **confirmed working on a
ZT7650-fitted r8q** (tested by an owner of one — this phone has the STM part);
on an STM unit the zinitix probe declines cleanly and touch is unaffected.

Touch **follows display rotation** (portrait and landscape both land correctly).
That took making the display look like a real built-in panel — see below.

### Display panel & power

The panel is scanned out by **simpledrm** from the framebuffer the UEFI lit — there
is no real mainline display driver yet. Two small touches make it behave like the
built-in panel it is:

- `patches/0006` makes simpledrm advertise a **DSI** connector instead of
  `Unknown`. mutter decides "is this a built-in panel?" purely from the connector
  type (eDP/LVDS/DSI/DPI), and only a built-in panel gets an integrated touchscreen
  mapped to it with the output rotation transform applied — so this is what makes
  touch follow rotation. A DT `panel` node (`width-mm`/`height-mm`) gives it a real
  physical size so it stops showing up as a 27″ display.
- **Suspend is disabled** on purpose. s2idle hard-resets this SoC, so the systemd
  sleep targets are masked; and now that a battery gauge and a built-in display
  exist, GNOME would otherwise idle- or critical-battery-suspend into that reset.
  A locked system dconf default (`rootfs/etc/dconf/…`) forces every power action to
  `nothing` and disables idle detection.

### Battery

The phone's charger and fuel gauge live in a Maxim **MAX77705** companion PMIC on
`i2c0` (`qupv3_se0`), which rides the same `r8q_force_fifo=1` geni path as the
touchscreen. Three i2c slaves matter: the ModelGauge fuel gauge at `0x36`, the top
PMIC/MUIC at `0x66`, and the charger at `0x69`.

- **Telemetry (read-only):** the fuel gauge is register-compatible with the
  mainline `max17042_battery` driver (`compatible = "maxim,max77705-battery"`), so
  the DT just adds a `fuel-gauge@36` node — no new driver.
  `/sys/class/power_supply/max170xx_battery` reports capacity, voltage, current and
  temperature.
- **Charging:** the `max77705` MFD (`pmic@66`) + `max77705-charger` (`charger@69`)
  drivers, with a `simple-battery` node supplying the charge parameters, drive the
  charger so the phone actually refills (`max77705-charger` shows `status =
  Charging`). This unit's MAX77705 reports silicon revision **PASS2**, which
  mainline's MFD rejects (it only whitelists PASS3), so `patches/0005` relaxes that
  check — the register layout is identical on PASS2.

`r8q-battery.service` loads all three modules after `r8q-touch.service` brings the
bus up. The fuel-gauge node is deliberately left IRQ-less so read-only telemetry
keeps working even if the charger/MFD ever fail to probe.

One caveat worth knowing: mainline has no driver for the MAX77705's MUIC, so the
port type is never detected and the charger stays at the USB-SDP default of
**500 mA**. A running GNOME session draws more than that, so the pack slowly
*discharges* while plugged in even though the charger reports `Charging`. The
service raises `input_current_limit` to 700 mA on start, which makes the net
battery current positive again. Raise it further at your own risk — it is the
host port, not the phone, that has to supply it.

### Wi-Fi

Wi-Fi is a discrete Qualcomm **QCA6390** on **PCIe** (not the on-SoC WCSS), driven
by `ath11k_pci` + MHI. Nothing needs to be enabled in the kernel config — ATH11K,
MHI, QRTR, `PCIE_QCOM`, `PCI_PWRCTRL_PWRSEQ` and `POWER_SEQUENCING_QCOM_WCN` are
all in `arm64` defconfig — and the firmware ships in `linux-firmware`
(`/lib/firmware/ath11k/QCA6390/hw2.0/`). The work is all device tree: a
`qca6390-pmu` that power-sequences the chip and drives WLAN_EN (tlmm gpio90) /
BT_EN (gpio76), `&pcie0` + `&pcie0_phy`, a `wifi@0` endpoint under `&pcieport0`,
and the PMIC rails those need (`vreg_s5a_1p9`, `vreg_s6a_0p95`, and a pm8150l
`regulators-1` node for `vreg_s8c_1p35`).

Two things will cost you a lot of time if you don't know them:

- **`PHY_QCOM_QMP_PCIE` is a module.** Until `phy-qcom-qmp-pcie.ko` is loaded,
  `1c00000.pcie` sits silently in `/sys/kernel/debug/devices_deferred` — the host
  bridge defers on the missing phy and prints nothing at all.
- **`qrtr-mhi.ko` must be installed and loaded.** MHI creates an `IPCR` channel
  device when the chip enters mission mode, and `qrtr-mhi` is what binds to it to
  carry QMI. Without it, ath11k stops at `Wait for device to enter SBL or Mission
  mode` and never says anything else — which reads exactly like a firmware that
  won't boot, even though the firmware is already running. If you hit that, build
  `mhi.ko` with `CONFIG_MHI_BUS_DEBUG=y` and read
  `/sys/kernel/debug/mhi/*/regdump`: `BHI_EXECENV: 0x2` means the device is in
  mission mode and the problem is above MHI, not in the firmware.

`r8q-wifi.service` loads the stack deliberately, in order, after the geni bus is
up: `phy-qcom-qmp-pcie` → `pwrseq-qcom-wcn` → `pci-pwrctrl-pwrseq` → wait for the
endpoint → `qrtr-mhi` → `ath11k_pci`. `r8q-wifi-blacklist.conf` stops udev from
coldplugging any of it at ~9 s, which otherwise races the touch/battery bring-up
on the same geni controller and produces SE0 i2c timeouts and MAX77705 IRQ storms.

Association is **NetworkManager**, so you can join a network from GNOME's own
Wi-Fi menu on the touchscreen instead of editing config over SSH. The one thing
that must be right is `NetworkManager/conf.d/10-r8q.conf`: it marks **`usb0`
unmanaged**, because that interface is the SSH lifeline and is configured
statically by systemd-networkd — let NM take it over and it will reconfigure the
interface out from under your session. `dns=none` for the same reason (the static
`/etc/resolv.conf` is what the USB tether relies on).

Note that the MAC address is random on every boot: this unit reports
`board_id 0xff` and no calibration data, so ath11k has no stored address to use.

Two things worth knowing about the log noise Wi-Fi produces:

- **AER correctable errors.** With PCIe ASPM enabled, the QCA6390 misses replay
  deadlines coming out of L0s/L1 and the link reports a stream of `Data Link
  Layer ... [12] Timeout` *correctable* errors whenever Wi-Fi goes active. They
  are harmless — the packet is retransmitted — but they flood the log. Measured
  over three scans: 6 with ASPM on, 0 with it off. `r8q-wifi.service` therefore
  disables ASPM on that one link, and it has to do so **after** `phy0` appears:
  ath11k disables ASPM for the firmware download and then calls `aspm_restore`,
  which puts it back.
- **They were reaching the panel because of the initramfs.** `/init` raises the
  console log level to 8 so early boot lands in the ESP logs, and nothing lowers
  it again — so `loglevel=3` on the cmdline is overridden for the whole session
  and every kernel message gets CPU-blitted onto the framebuffer.
  `sysctl.d/50-r8q-printk.conf` puts it back to 4 once userspace is up. That is
  worth more than quiet: it took boot from 21 s back down to **~12 s**, the same
  lever as the original `loglevel=3` change.

---

## Roadmap

The device boots to an accelerated KDE Plasma Mobile session you can touch and
SSH into. What's left, roughly in the order it's worth doing:

| Goal | What it needs | Notes |
|------|---------------|-------|
| **Bluetooth** | QCA6390 BT (`hci_qca` over UART/serdev) | Same chip as Wi-Fi, and the `qca6390-pmu` in the DT already drives its BT_EN line — so the power sequencing is done and this is the cheapest remaining win. |
| **USB host mode** | dwc3 role switch + VBUS (`pm8150b` regulator or powered OTG hub) | Currently peripheral-only (that's how SSH works). Host mode gets a real keyboard/mouse. Needs a role-switch path and VBUS supply. |
| **Greeter / lock screen** | Replace sddm autologin with a real login | Plasma Mobile already ships `plasma-keyboard` as an on-screen keyboard, so a headless login is now viable. Pure userspace/config work; no kernel changes. |
| **Audio** | LPASS + WCD938x codec + `cs35l41` speaker amps (SoundWire) | The hardest mainline bring-up here; lowest priority for a dev device. |
