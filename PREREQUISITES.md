# Prerequisites

## The phone
- **Samsung Galaxy S20 FE 5G Snapdragon** — codename **`r8q`**, SoC **SM8250**
  (Snapdragon 865). This is the *Snapdragon* variant (SM-G781x), **not** the
  Exynos S20 FE.
- **Unlocked bootloader.** (OEM unlock enabled; the flash will simply be rejected
  if it's locked.)
- **A verification-disabled `vbmeta` already flashed** — e.g. you're coming from
  LineageOS. Custom images on `BOOT` won't boot under AVB otherwise. If you're on
  stock, flash a `vbmeta` with `avbtool make_vbmeta_image --flags 2
  --padding_size 4096` first (this is a destructive step).

> ⚠️ **This wipes your `userdata` partition.** Android (or whatever Linux was
> there) is sacrificed for the Arch rootfs. Back up anything you care about.

## Host packages (Arch/derivatives shown; adapt for your distro)
- `heimdall` (the Grimler fork, v2.2.2+ — handles 2020+ Samsungs) for Odin-protocol flashing
- `clang` / `llvm` / `lld` (kernel is built with `LLVM=1`), `make`, `bc`, `flex`, `bison`, `dtc`
- `aarch64-linux-gnu-gcc` (or clang cross) toolchain bits as needed
- `python` + `python-venv` (for Mu-Silicium's edk2 pytools), `mono`/`dotnet` per Mu-Silicium docs
- `bsdtar` (libarchive), `curl`, `openssl`
- `avbtool` (only if you need to flash vbmeta)
- `iptables` + a working internet uplink on the host (for USB tethering)
- optional: `python-pexpect` (drive the phone's ssh password without `sshpass`)

## Sources you'll clone
- **Mainline Linux** (7.3.5 is used here): the r8q DT is upstream since v6.18.
- **Mu-Silicium** — `github.com/sitsirK/Mu-Silicium`, branch `r8q`: upstream
  (`Project-Silicium/Mu-Silicium`) plus SD-card support and the r8q device tree.
- **Arch Linux ARM** aarch64 rootfs tarball (downloaded by `install-arch.sh`).

## Key combos
- **Download mode:** power off → hold **VolUp + VolDown** → plug USB.
- **Boot UEFI / mass storage:** after flashing, the phone boots Mu-Silicium from
  `BOOT` on power-on. Mass-storage and boot-menu are reached from Mu-Silicium's
  volume-key UI.
