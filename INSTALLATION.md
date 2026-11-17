# Installation

This gets you a booting **Arch Linux ARM** on the r8q, reachable from your PC
over the USB cable (SSH + internet). Read [`PREREQUISITES.md`](PREREQUISITES.md)
first — **this wipes `userdata`.**

Throughout: `$KSRC` = your mainline kernel source, `$OUT` = its build dir
(`O=`), `$MUSIL` = your Mu-Silicium checkout. `KV` is the kernel release (e.g.
`7.1.2`).

Two ways in:
- **The alarminstall image** (next section): flash UEFI once (§2–3), boot the
  installer from a microSD card, pick a desktop with the volume keys. No kernel
  build, no mass-storage mode.
- **By hand** (§1–8): build everything yourself, install from the PC.

---

## 0. The alarminstall image

[alarminstall](https://github.com/sitsirK/alarminstall) is archinstall adapted
to this phone, on a bootable image. It installs Arch Linux ARM with the r8q
kernel, GPU acceleration, touch, Wi-Fi and a desktop (Plasma Mobile, GNOME and
Sway are tested). It **erases `userdata`** and formats `cache` as the ESP; the
partition table is not changed.

**UEFI with SD-card support.** Upstream Mu-Silicium does not see the SD card on
this phone. Build the `r8q` branch of
[sitsirK/Mu-Silicium](https://github.com/sitsirK/Mu-Silicium/tree/r8q): upstream
plus SD-slot power, an "SD Card" boot-menu entry and the release's device tree,
ready to build (Linux, ~5 GB of source):

```bash
git clone --recursive -b r8q https://github.com/sitsirK/Mu-Silicium.git
cd Mu-Silicium
./setup_env.sh -p pacman              # or apt / dnf: compilers, mono, nasm, pip packages
python3 build_uefi.py -d r8q          # -> Mu-r8q.img
```

Flash `Mu-r8q.img` (§3). The boot menu now lists **SD Card**.

**The card.** Download `alarminstall-r8q-<date>.iso` and `SHA256SUMS` from this
repository's Releases, then:

```bash
sha256sum -c SHA256SUMS --ignore-missing
sudo dd if=alarminstall-r8q-<date>.iso of=/dev/<sdcard> bs=4M conv=fsync
```

or copy the `.iso` onto a [Ventoy](https://www.ventoy.net) card (several
versions side by side are fine).

**Boot it.** Reboot, press **Vol-Up** at "[Volume Up] Boot Manager", pick
**SD Card**. About 50 s later the installer is on the screen: **Vol-Up /
Vol-Down** move (hold to scroll), **Power** selects. Choices are marked: plain =
tested, yellow = untested, red and struck through = not supported yet.

**Get online.** Packages are downloaded during the install, and the phone has
no keyboard for a Wi-Fi password. Plug it into a PC (the PC gets an address over
USB; the bar at the bottom of the phone's screen shows where to connect):

```bash
ssh root@172.16.42.1                  # password root; the host key changes every boot
nmtui                                 # or: nmcli dev wifi connect "NAME" password "PASSWORD"
tmux attach -t alarminstall           # the same installer, with your keyboard
```

If it gave up waiting for the network, type `alarminstall`. The Wi-Fi network
is copied to the installed system. A Linux PC can share its own connection
instead: [`scripts/host-tether.sh`](scripts/host-tether.sh) (§8).

**After the install** pick reboot; internal storage boots first again. Hostname
`alarm`, root password `alarm`, user `alarm` / `alarm` (sudo). Root can log in
with that password over SSH (USB and Wi-Fi): **change both** after install or in alarminstall if you did it via ssh or a usb keyboard (`passwd`). The
installed system serves no addresses over USB: give the PC `172.16.42.14` as in
§7.

The image carries linux-firmware's QCA6390 Wi-Fi firmware. The Samsung-signed
GPU zap shader is not on it: the installer copies it from your phone (§9).

---

## 1. Build the kernel (Image + DTB)

Drop the two device-tree files from [`dts/`](dts/) into
`$KSRC/arch/arm64/boot/dts/qcom/` (they carry the display fix).
`build_kernel.sh` also applies the kernel patches from [`patches/`](patches/)
(required for the display driver and GPU acceleration later — harmless
otherwise). Then:

```bash
# arm64 defconfig + our fragment, LLVM=1, bring-up drivers built-in
KSRC=... OUT=... ./scripts/build_kernel.sh
```

The kernel is built with:
- an **embedded switch-root initramfs** from [`initramfs/`](initramfs/)
  (`CONFIG_INITRAMFS_SOURCE` = the dir with `init` + `irfs.devnodes`; you also
  need a static aarch64 busybox in `bin/busybox`),
- **`CONFIG_CMDLINE_FORCE`** set to the string in
  [`config/cmdline.txt`](config/cmdline.txt) (the phone has no keyboard, so the
  cmdline is baked in). Keep `simpledrm` **enabled**: it is the boot console
  until `msm` takes the display over (§13).

Outputs: `$OUT/arch/arm64/boot/Image` and
`$OUT/arch/arm64/boot/dts/qcom/sm8250-samsung-r8q.dtb`.

## 2. Embed the DTB and build UEFI

Mu-Silicium carries a copy of the DTB **inside the firmware** and exposes it via
`DtPlatformDxe`. (The kernel does not boot from this copy — it loads `r8q.dtb`
from the ESP, see step 5 — so later device-tree changes do not need a re-flash.)
Use the `r8q` branch of sitsirK/Mu-Silicium (§0): it adds SD-card support and
already enables the "Device Tree" FREEFORM block in
`$MUSIL/Platforms/Samsung/r8qPkg/r8q.fdf` (on upstream, un-comment it yourself).
To embed the DTB you built:

```bash
MUSIL=$MUSIL DTB=$OUT/arch/arm64/boot/dts/qcom/sm8250-samsung-r8q.dtb ./scripts/build-uefi.sh
# -> $MUSIL/Mu-r8q.img
```

## 3. Flash UEFI to BOOT

Put the phone in **download mode** (power off; VolUp+VolDown; plug USB):

```bash
./scripts/flash.sh $MUSIL/Mu-r8q.img         # heimdall flash --BOOT ...; it reboots
```

The phone now boots Mu-Silicium UEFI on every power-on.

## 4. Prepare the ESP (once)

Boot the phone into Mu-Silicium **mass-storage** mode. The ESP is the phone's
`cache` partition — reformat it vfat once (UFS logical block is 4096):

```bash
ESP=$(lsblk -o NAME,PARTLABEL -rn | awk '$2=="cache"{print "/dev/"$1}')
sudo mkfs.vfat -F 32 -S 4096 -n R8QESP "$ESP"
```

## 5. Deploy the kernel Image and the DTB to the ESP

Still in mass-storage mode:

```bash
./scripts/deploy-esp.sh $OUT/arch/arm64/boot/Image \
                        $OUT/arch/arm64/boot/dts/qcom/sm8250-samsung-r8q.dtb
#   -> ESP:/EFI/BOOT/BOOTAA64.EFI   and   ESP:/r8q.dtb
```

**Both files are required.** The forced command line contains `dtb=r8q.dtb`, so
the kernel's EFI stub loads the device tree from the root of the ESP. If the file
is not there it does **not** fall back to the firmware's copy: it stops with
`Failed to load device tree!`, which Mu-Silicium reports as *Failed to find an
operating system*.

This is also what makes later changes cheap. The running phone can mount its own
ESP, so a new device tree (or a new `Image`, copied over
`EFI/BOOT/BOOTAA64.EFI` the same way) is one copy and a reboot — no mass-storage
mode, no re-flash:

```bash
scp $OUT/arch/arm64/boot/dts/qcom/sm8250-samsung-r8q.dtb root@172.16.42.1:/root/r8q.dtb
ssh root@172.16.42.1 'mkdir -p /mnt/esp && mount /dev/disk/by-partlabel/cache /mnt/esp &&
    cp /mnt/esp/r8q.dtb /mnt/esp/r8q.dtb.bak && cp /root/r8q.dtb /mnt/esp/r8q.dtb &&
    sync && umount /mnt/esp'
```

Keep the `.bak`: a device tree that does not boot can only be put back from
mass-storage mode.

## 6. Install Arch onto userdata

Still in mass-storage mode (this **formats userdata**):

```bash
KV=7.1.2 OUT=$OUT KSRC=$KSRC ./scripts/install-arch.sh
```

It extracts Arch Linux ARM, **moves the kernel module tree aside** (cold-plugging
the full tree hard-resets the SoC — see the note in the script), lays down our
[`rootfs/`](rootfs/) overlay, enables `sshd` + `systemd-networkd` +
`r8q-usb-gadget`, sets root autologin on `tty1`, root password `root`, and
disables the pacman sandbox (our kernel has no Landlock).

## 7. Boot

Exit mass storage and let the phone boot. You should see the panel show the
switch-root message, then systemd, then a root shell (autologin). On the PC an
NCM network device appears:

```bash
DEV=<the new cdc_ncm netdev>
sudo ip addr add 172.16.42.14/24 dev "$DEV"; sudo ip link set "$DEV" up
ssh root@172.16.42.1            # password: root
```

## 8. USB tethering (internet + pacman)

Share the PC's internet to the phone (host NAT is runtime — re-run after a PC
reboot):

```bash
./scripts/host-tether.sh        # enables ip_forward + MASQUERADE for 172.16.42.0/24
```

The phone already has `Gateway=172.16.42.14` + DNS baked into
`rootfs/etc/systemd/network/20-usb0.network`, so once the host NAT is up:

```bash
ssh root@172.16.42.1 'ping -c2 archlinux.org'
# first pacman use on a fresh rootfs:
ssh root@172.16.42.1 'pacman-key --init && pacman-key --populate archlinuxarm && pacman -Sy'
```

## 9. GPU acceleration (Adreno 650) + sway

Prereq: the kernel was built **with the [`patches/`](patches/) applied**
(`build_kernel.sh` does this) and its modules are installed on the rootfs —
at minimum `msm.ko` and its dependencies under `/lib/modules/$KV/`, plus the
three display modules from §13.

**a) Userspace + generic firmware** (on the phone, over SSH):

```bash
pacman -S mesa vulkan-freedreno linux-firmware-qcom sway foot seatd
systemctl enable --now seatd
```

That provides `/lib/firmware/qcom/a650_sqe.fw` and `a650_gmu.bin`.

**b) The zap shader — from YOUR device's stock firmware.** Samsung's TrustZone
only authenticates a **Samsung-signed** zap; the generic
`qcom/sm8250/a650_zap.mbn` from linux-firmware is rejected (`-22`) and the GPU
then silently drops every render write.

**It is already on the phone — you do not need to download stock firmware.** The
signed PIL images live on the **`apnhlos`** partition (what Android mounts at
`/vendor/firmware_mnt`). It is *not* inside `super.img`, and `/vendor/firmware/`
holds only the unsigned blobs (`a650_sqe.fw`, `a650_gmu.bin`) — so extracting the
`vendor` image will never find the zap. Copy it straight off the phone over SSH:

```bash
mkdir -p /mnt/fw && mount -o ro /dev/disk/by-partlabel/apnhlos /mnt/fw
ls -l /mnt/fw/image | grep -i zap
#   want: a650_zap.mdt, a650_zap.b00, a650_zap.b01, a650_zap.b02

install -Dm644 /mnt/fw/image/a650_zap.mdt /lib/firmware/qcom/sm8250/a650_zap.mbn
for s in b00 b01 b02; do
  install -Dm644 /mnt/fw/image/a650_zap.$s /lib/firmware/qcom/sm8250/a650_zap.$s
done
umount /mnt/fw
```

The `.mdt` is deliberately renamed to `.mbn`; the `.bNN` segments keep their
names. Resulting layout:

```
/lib/firmware/qcom/sm8250/a650_zap.mbn    <- the stock a650_zap.mdt, renamed
/lib/firmware/qcom/sm8250/a650_zap.b00
/lib/firmware/qcom/sm8250/a650_zap.b01
/lib/firmware/qcom/sm8250/a650_zap.b02
```

You have just overwritten a file owned by `linux-firmware-qcom` — see
[Protect the Samsung zap shader from pacman](#protect-the-samsung-zap-shader-from-pacman)
below before your next `-Syu`.

**c) Module options + post-boot load.** The [`rootfs/`](rootfs/) overlay ships
these (already in place if you re-ran the overlay):

- `etc/modprobe.d/r8q-gpu.conf` — `blacklist msm` **plus**
  `options msm separate_gpu_kms=1 r8q_zap_dyn=1 r8q_zap_secvid=0`.
  `r8q_zap_dyn=1` is **required**: it loads the zap into dynamically allocated
  RAM; pointing it at the DT carveout makes Samsung's TZ **hard-reset the SoC**.
- `etc/systemd/system/r8q-gpu.service` — loads `msm` after `multi-user.target`
  (never let udev coldplug it) and waits for the msm display (§13).
  `systemctl enable r8q-gpu.service`.
- `root/.bash_profile` — tty1 autologin waits for `renderD128` and the msm
  display, then starts **sway** with the vulkan (turnip) renderer: render node
  `renderD128`, scanout on the msm display card.

**d) Verify** (after a reboot):

```bash
ssh root@172.16.42.1 'ls /dev/dri; dmesg | grep -i zap'
# want: renderD128 present, "r8q: zap region dma_alloc'd at ..." and NO "zap auth failed"
```

Sway should be on the panel. Rules of the road: **never `rmmod msm`** (GMU/IOMMU
teardown wedges the kernel — load once per boot), and never write the SECVID
registers from the kernel (the hypervisor traps them; that is what
`r8q_zap_secvid=0` keeps disabled).

## 10. Wi-Fi (QCA6390 over PCIe)

No kernel config changes are needed — ATH11K(+PCI), MHI, QRTR, `PCIE_QCOM`,
`PCI_PWRCTRL_PWRSEQ` and `POWER_SEQUENCING_QCOM_WCN` are all in `arm64`
defconfig. The DT nodes are in [`dts/`](dts/) and the firmware comes from
`linux-firmware`.

**a) Modules and firmware on the phone.** `make modules_install` must have put
these under `/lib/modules/$KV/`, and one of them is easy to miss:

```bash
ssh root@172.16.42.1 'ls /lib/firmware/ath11k/QCA6390/hw2.0/'   # amss.bin board-2.bin m3.bin
ssh root@172.16.42.1 'modinfo qrtr-mhi | head -2'               # MUST be present
```

If `qrtr-mhi.ko` is missing, install it and re-run `depmod -a`. Without it
nothing binds to the MHI `IPCR` channel, QMI never starts, and ath11k stops
dead at `Wait for device to enter SBL or Mission mode` with no further output —
which looks like a firmware failure but is not one.

**b) Overlay + service.** The [`rootfs/`](rootfs/) overlay ships:

- `etc/modprobe.d/r8q-wifi-blacklist.conf` — keeps udev from coldplugging the
  Wi-Fi stack at ~9 s, which races the touch/battery geni bring-up (SE0 i2c
  timeouts + MAX77705 IRQ storms).
- `etc/systemd/system/r8q-wifi.service` — loads it deliberately instead, in
  order: `phy-qcom-qmp-pcie` (the PCIe **phy is a module**; without it
  `1c00000.pcie` silently defers) → `pwrseq-qcom-wcn` → `pci-pwrctrl-pwrseq` →
  wait for the endpoint → `qrtr-mhi` → `ath11k_pci`.
- `etc/NetworkManager/conf.d/10-r8q.conf` — see (c).

```bash
ssh root@172.16.42.1 'systemctl enable --now r8q-wifi.service'
ssh root@172.16.42.1 'dmesg | grep ath11k'   # want: fw_version ..., "renamed from wlan0"
```

**c) NetworkManager, so you can connect from the GNOME UI.** Install it *before*
starting it, and put the config in place first — the config is what keeps NM off
`usb0`, and `usb0` is the SSH connection you are typing over:

```bash
pacman -S networkmanager wireless-regdb
install -Dm644 rootfs/etc/NetworkManager/conf.d/10-r8q.conf \
               /etc/NetworkManager/conf.d/10-r8q.conf   # usb0 unmanaged, dns=none
systemctl enable --now NetworkManager
systemctl disable NetworkManager-wait-online.service    # else it stalls boot
nmcli device status      # want: wlp1s0 managed, usb0 "unmanaged"
```

Two gotchas:

- If `nmcli` dies with `libnm.so.0: version 'libnm_1_xx_0' not found`, you did a
  partial upgrade (`pacman -Sy networkmanager` against an older `libnm`). Fix with
  `pacman -S libnm`. The daemon runs regardless, but every client — `nmcli`,
  gnome-control-center, the GNOME shell menu — is broken until the versions match.
- Do package installs over a transient link with
  `systemd-run --unit=install --collect pacman -S ...` so an SSH drop cannot
  abort the transaction half-way.

Then join a network from **Settings → Wi-Fi** on the phone itself, or over SSH:

```bash
nmcli device wifi list
nmcli device wifi connect 'YOUR-SSID' password 'YOUR-PASSPHRASE'
```

NM stores the connection in `/etc/NetworkManager/system-connections/`, so it
reconnects on its own after a reboot.

**Debugging note.** If MHI ever stalls again, build `mhi.ko` with
`CONFIG_MHI_BUS_DEBUG=y` and read `/sys/kernel/debug/mhi/*/regdump`. It prints
`BHI_EXECENV` / `BHI_STATUS` / `BHI_ERRCODE` / `BHI_ERRDBG1-3` — PBL's own
verdict on the firmware. `BHI_EXECENV: 0x2` means the chip is already in mission
mode and the fault is above MHI, not in the firmware.

---

## 11. The CPU wedge — an open bug and its partial mitigation

**This is not fixed.** Every so often one CPU core simply stops executing while
the other seven carry on, and the phone dies shortly afterwards. It is not a
display, GPU or thermal fault and it is not tied to a workload: it has happened
during a compile, inside a game, and on a nearly idle phone with nothing but an
SSH session open.

How to recognise it: **the kernel keeps answering ICMP while userspace stops** —
`ping` stays at ~2 ms while `ssh` fails with `Connection timed out during banner
exchange`. The kernel log shows an RCU stall naming one CPU, followed by an NMI
backtrace request that this CPU never answers. It usually degrades to a full hang
or a reset within a minute or two; recovery is the physical VolUp+Power combo.

What has been measured so far:

- **Any core can die** — the Cortex-A55s (cpu0-3) as well as the A77s (cpu4-7),
  sometimes two or three of them within a second.
- **The core is not asleep, it has stopped.** Idle cores answer the NMI backtrace
  request (`skipped: idling at cpu_do_idle`); the dead one prints nothing at all.
  The one time a dying core was function-traced, its last call was in the cpuidle
  governor (`menu_select()`) — ordinary C code, *before* it ever reached WFI.
- **It is not the deep idle state.** It reproduces with `state1` disabled on all
  eight cores and not a single power-collapse entry since boot. Earlier versions
  of this page blamed `cpu7` and the `cpu-sleep-1-0` state, and then lost
  wake-ups from WFI. Both were wrong.
- **One dead core takes the whole phone with it** because of what queues up
  behind it: everything that needs an all-CPU IPI (which is why the backtraces
  you do see are innocent victims in `kick_all_cpus_sync ← __text_poke`), and,
  when the dead core is cpu0, every RPMh request — the `apps_rsc` interrupt is
  affine to cpu0, hence `rpmh_write_batch ... Error sending AMC RPMH requests
  (-110)`.

The cause is still unknown. The working theory is that the core loses its clock
(a CPU frequency transition that never completes), but that is unproven.

**What does not fix it:** a "heartbeat" that wakes every core from a per-CPU
timer every few tens of milliseconds. The watchdog used to catch the wedge does
exactly that, one pinned thread per core every 10 ms, and cores died while it ran.

**a) Disable the deep idle state on every core.** Worth installing, but the case
for it is purely empirical: the phone wedged within minutes of desktop use before
it and has run for days with it. Cores are still lost with it applied, so read it
as "rarer", not "fixed".

```bash
install -Dm644 rootfs/etc/tmpfiles.d/50-r8q-cpuidle.conf \
               /etc/tmpfiles.d/50-r8q-cpuidle.conf
systemd-tmpfiles --create /etc/tmpfiles.d/50-r8q-cpuidle.conf

# verify: no core power-collapses any more
for c in 0 1 2 3 4 5 6 7; do echo -n "cpu$c=$(cat /sys/devices/system/cpu/cpu$c/cpuidle/state1/disable) "; done; echo
#   want: all 1
```

**b) `r8q-noidle` (optional, unproven).** A `SCHED_IDLE` spinner pinned to each
core, so the idle loop is almost never entered. It was written for the
lost-wake-up theory, which is dead; it is kept because the one traced death did
happen on the way into idle. There is **no measurement showing that it prevents
the wedge** — idle-entry rate alone is not the trigger (15 million forced idle
entries in 75 s did not wedge the phone) — and it costs power and heat, since no
core ever sleeps while it runs. Use it to experiment, not as a fix, and never as
a boot service.

```bash
install -Dm755 rootfs/usr/local/sbin/r8q-noidle.sh /usr/local/sbin/r8q-noidle.sh
install -Dm644 rootfs/etc/systemd/system/r8q-noidle.service \
               /etc/systemd/system/r8q-noidle.service
systemctl daemon-reload

systemctl start r8q-noidle      # ... heavy work ...
systemctl stop r8q-noidle
```

## 12. KDE Plasma Mobile

```bash
systemd-run --unit=install --collect pacman -S plasma-mobile plasma-settings kscreen sddm
```

**a) Stop PowerDevil from suspending — do this BEFORE the first login.** Suspend
is a hard reset on this device (see the sleep-target masking earlier), and
PowerDevil will happily idle-suspend into it.

```bash
for f in powerdevilrc powermanagementprofilesrc kscreenlockerrc; do
  install -Dm644 rootfs/etc/xdg/$f /etc/xdg/$f
done
```

`powermanagementprofilesrc` deliberately omits the `[*][SuspendSession]` group in
every profile, `powerdevilrc` sets `BatteryCriticalAction=0` (the fuel gauge reads
critical while the pack is fine), and `kscreenlockerrc` disables auto-locking —
with autologin and no hardware keyboard, a lock screen is an easy way to lock
yourself out of the panel. These live in `/etc/xdg` safely:
`plasma-mobile-envmanager` only generates `~/.config/plasma-mobile/{kwinrc,
kdeglobals,ksmserverrc}` and never touches them.

**b) sddm.** There is no Xorg on this device at all, and sddm still defaults its
Wayland greeter to weston, so both settings are required:

```bash
install -Dm644 rootfs/etc/sddm.conf.d/10-r8q.conf /etc/sddm.conf.d/10-r8q.conf
install -Dm644 rootfs/etc/systemd/system/sddm.service.d/r8q-after-gpu.conf \
               /etc/systemd/system/sddm.service.d/r8q-after-gpu.conf
systemctl daemon-reload
systemctl disable gdm && systemctl enable sddm
```

The `r8q-after-gpu.conf` drop-in is load-bearing: KWin picks its render device
once at startup, so if sddm beats `r8q-gpu.service` the session silently runs on
llvmpipe.

**c) Verify it got the GPU.**

```bash
ls -l /proc/$(pgrep -x kwin_wayland)/fd | grep -o '/dev/dri/[a-zA-Z0-9]*' | sort | uniq -c
#   want: 3 of the msm display card (/dev/dri/card2 here)   and   8 /dev/dri/renderD128
```

KWin needs no GPU configuration of its own — do **not** port GNOME's
`mutter-device-preferred-primary` udev tag or `MUTTER_DEBUG_MULTI_GPU_FORCE_COPY_MODE`
across. It has a real split display/render-device concept, treats every
`DRM_BUS_PLATFORM` node as compatible and prefers the non-software renderer, and
both of ours are platform-bus. If it ever guesses wrong, force it with
`KWIN_RENDER_NODES=/dev/dri/renderD128`.

Scale is automatic: KWin's phone-panel DPI heuristic works from the physical
size the panel driver reports (67 × 150 mm on a DSI connector). Check with
`kscreen-doctor -o`, which needs `WAYLAND_DISPLAY` (`wayland-0` or `wayland-1`,
see `/run/user/1000`) in addition to the usual `XDG_RUNTIME_DIR` /
`DBUS_SESSION_BUS_ADDRESS`.

GNOME stays installed; revert with `systemctl disable sddm && systemctl enable gdm`.

## 13. Display: mainline msm-drm, 120 Hz, brightness

Without this the panel shows the framebuffer the bootloader lit, scanned out
through `simpledrm`: 60 frames/s, no brightness control (desktops only dim the
pixels), no real screen-off, and the compositor copies every frame on the CPU.
With it, `msm` drives the display engine and the DSI link itself and
[`patches/0012`](patches/) drives the panel:

- **120 Hz** with real vblank; KWin scans out straight from the GPU,
- **hardware brightness**: `/sys/class/backlight/ae94000.dsi.0` (0–1023), which
  is what the desktop's brightness slider then drives,
- **screen off** really powers the panel down.

**a) Check which panel you have.** The r8q was built with one of three panels,
and `patches/0012` supports the **S6E3FC3 / AMS646YD01**. Samsung's bootloader
logs the one it found:

```bash
mkdir -p /mnt/logfs && mount -o ro /dev/disk/by-label/LOGFS /mnt/logfs
grep -a -o 'dsi_display0=ss_dsi_panel_[A-Z0-9_]*' /mnt/logfs/UefiLog1.txt | tail -1
#   want: dsi_display0=ss_dsi_panel_S6E3FC3_AMS646YD01_FHD   (lcd_id=0x805081)
umount /mnt/logfs
```

On an EA8079B or EA8076A panel, stop here and keep the `simpledrm` setup (leave
out the display block of the device tree). The vendor dtbo carries their init
sequences too, so a driver for them is mostly transcription.

**b) Kernel and device tree.** `build_kernel.sh` applies all three patches, and
the display block sits at the end of
[`dts/sm8250-samsung-r8q.dts`](dts/sm8250-samsung-r8q.dts):

- `0010` stops `dispcc` from parking the MDP clock when it registers. Without
  it the boot console turns into coloured garbage a few seconds into boot and
  goes black until `msm` takes over.
- `0011` stops msm's DSI host from reprogramming its PLL before every panel
  command. Without it every brightness change corrupts the next frame (garbage
  blocks; `dsi_err_worker: status=4`, `frame done timeout`).
- `0012` is the panel driver, `CONFIG_DRM_PANEL_SAMSUNG_S6E3FC3=m` in
  [`config/r8q_bringup.config`](config/r8q_bringup.config).

`0010` is built into the `Image`, so deploy both the `Image` and the DTB (§5).

**c) Modules.** `msm.ko` already contains the DPU, DSI and DSI PHY drivers.
Three more modules must be on the phone, and the DSI host waits forever,
without a word, if the refgen one is missing:

```bash
for m in panel-samsung-s6e3fc3 backlight qcom-refgen-regulator; do modinfo -n $m; done
```

Install any that are missing from `$OUT` and run `depmod -a`.

**d) Load order.** `r8q-gpu.service` (§9) loads `msm` once and then waits up
to 10 s for the msm display, and sddm starts after it (§12b). If KWin started
earlier it would open `simpledrm` just before `msm` removes it.

**e) Verify** after a reboot:

```bash
dmesg | grep -E 'lcd_id|msm-kms'
#   want: panel-samsung-s6e3fc3 ae94000.dsi.0: S6E3FC3/AMS646YD01, lcd_id 0x805081
#         [drm] Initialized msm-kms ... for ae01000.display-controller
ls /sys/class/backlight                           # ae94000.dsi.0
dmesg | grep -c -E 'dsi_err|frame done timeout'   # want: 0
```

`kscreen-doctor -o` should list `1080x2400@120.00` as the current mode. If the
KWin config still holds a custom mode from the `simpledrm` days, switch to the
native mode and remove the custom one: its CVT timings put the DSI link at the
wrong rate.

Two rules: **never `rmmod msm`** (§9), and **never read the display block's
registers through `/dev/mem`** once `msm` owns it — it power-gates the block,
and an access then hard-resets the phone. The sway autologin finds the msm
display by itself; GNOME's udev tag (`61-mutter-primary-gpu.rules`) dates from
the `simpledrm` setup and GNOME on msm-drm is untested.

To go back, put a `r8q.dtb` built without the display block on the ESP; the
`Image` with `0010`–`0012` works with either.

## Protect the Samsung zap shader from pacman

`/usr/lib/firmware/qcom/sm8250/a650_zap.mbn` is **owned by `linux-firmware-qcom`**,
and step 9 overwrote it with your Samsung-signed blob. Any upgrade of that package
silently restores the upstream file and the GPU then hangs on its first submit. Add
this to `/etc/pacman.conf` once:

```
NoUpgrade = usr/lib/firmware/qcom/sm8250/a650_zap.mbn
```

pacman will drop the upstream file as `.pacnew` instead. Verify at any time with
`md5sum /usr/lib/firmware/qcom/sm8250/a650_zap.mbn` against your saved copy.

Two more things that bite on a fresh ALARM rootfs:

- `/` and `/usr` may be owned by `alarm` (a tarball-extraction artifact, same as
  `/etc`). `systemd-tmpfiles` then fails during package installs with
  `Detected unsafe path transition / (owned by alarm) → /dev`. Fix once with
  `chown root:root / /usr && chmod 755 /`.
- **`systemctl reboot` does not come back by itself.** Returning to Linux needs
  the physical **VolUp+Power with USB connected** combo, so never reboot a phone
  that nobody can reach. (Mu-Silicium is on `BOOT`, as flashed in step 3; the
  stock `RECOVERY` partition is left alone.)
