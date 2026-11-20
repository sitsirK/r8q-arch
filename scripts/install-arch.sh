#!/usr/bin/env bash
#
# Install Arch Linux ARM onto the phone's userdata partition + lay down our
# services/config. Run with the phone in Mu-Silicium MASS-STORAGE mode.
#
# WARNING: DESTROYS the userdata partition (Android / any prior Linux install).
#
# Env: KV=<kernel release, e.g. 7.3.5>  OUT=<kernel build dir>  KSRC=<kernel source dir>
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"          # repo root
KV="${KV:?set KV to the kernel release (e.g. 7.3.5)}"
OUT="${OUT:?set OUT to your kernel build dir (has modules)}"
KSRC="${KSRC:?set KSRC to the kernel source dir}"
MNT="${MNT:-/mnt/r8qroot}"
TARBALL_URL="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"

# Identify userdata by GPT PARTLABEL — never guess the device letter.
UD="$(lsblk -o NAME,PARTLABEL -rn | awk '$2=="userdata"{print "/dev/"$1}')"
[ -n "$UD" ] || { echo "!! userdata not found — is the phone in mass-storage mode?"; exit 1; }
echo "!! About to FORMAT $UD (userdata) as ext4 'archroot' — all data on it is LOST."
read -rp "Type YES to continue: " ok; [ "$ok" = YES ] || exit 1

sudo mkfs.ext4 -F -L archroot "$UD"
sudo mkdir -p "$MNT"; sudo mount "$UD" "$MNT"

echo "[*] downloading + extracting Arch Linux ARM aarch64"
tmp="$(mktemp -d)"; curl -L "$TARBALL_URL" -o "$tmp/alarm.tgz"
sudo bsdtar -xpf "$tmp/alarm.tgz" -C "$MNT" --numeric-owner; sync

# Kernel modules: install, then MOVE ASIDE. Cold-plugging the full tree hard-resets
# the SoC (qcom_wdt=m takes over the firmware-armed APSS watchdog -> bite ~30 s later;
# adsp/cdsp/slpi remoteproc coldplug is also lethal). Everything needed for bring-up
# is built-in, so udev must cold-plug nothing. Reintroduce a pruned allowlist later.
sudo make -C "$KSRC" O="$OUT" ARCH=arm64 LLVM=1 INSTALL_MOD_PATH="$MNT" modules_install
sudo depmod -b "$MNT" "$KV"
sudo mv "$MNT/lib/modules/$KV" "$MNT/lib/modules/$KV.disabled"

echo "[*] laying down rootfs overlay + config"
sudo cp -a "$HERE/rootfs/." "$MNT/"

# Enable services via wants symlinks (no chroot / qemu-binfmt needed).
sudo mkdir -p "$MNT/etc/systemd/system/multi-user.target.wants" \
              "$MNT/etc/systemd/system/sockets.target.wants"
sudo ln -sf /etc/systemd/system/r8q-usb-gadget.service \
            "$MNT/etc/systemd/system/multi-user.target.wants/r8q-usb-gadget.service"
sudo ln -sf /usr/lib/systemd/system/systemd-networkd.service \
            "$MNT/etc/systemd/system/multi-user.target.wants/systemd-networkd.service"
sudo ln -sf /usr/lib/systemd/system/systemd-networkd.socket \
            "$MNT/etc/systemd/system/sockets.target.wants/systemd-networkd.socket"
# sshd already enabled in the tarball; allow root password login (no keyboard -> ssh is the way in)
printf '\n# r8q bring-up\nPermitRootLogin yes\nPasswordAuthentication yes\n' | sudo tee -a "$MNT/etc/ssh/sshd_config" >/dev/null
# root password = root
HASH="$(openssl passwd -6 root)"; sudo sed -i "s|^root:[^:]*:|root:${HASH//|/\\|}:|" "$MNT/etc/shadow"
# pacman: our kernel has no Landlock -> disable the download sandbox
grep -q '^DisableSandbox' "$MNT/etc/pacman.conf" || sudo sed -i '/^\[options\]/a DisableSandbox' "$MNT/etc/pacman.conf"
# fstab / hostname / persistent journal
echo 'LABEL=archroot  /  ext4  rw,relatime  0 1' | sudo tee "$MNT/etc/fstab" >/dev/null
echo r8q | sudo tee "$MNT/etc/hostname" >/dev/null
sudo mkdir -p "$MNT/var/log/journal"

sync; sudo umount "$MNT"
echo "[+] Arch installed on $UD (LABEL=archroot). Boot the phone; then: ssh root@172.16.42.1 (pw: root)"
