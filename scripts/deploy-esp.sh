#!/usr/bin/env bash
# Copy the kernel Image (as BOOTAA64.EFI) and the device tree (as r8q.dtb) to the ESP.
# Phone must be in Mu-Silicium MASS-STORAGE mode.
# The ESP is the phone's `cache` partition, reformatted vfat (label R8QESP).
#
# The DTB is not optional on a fresh ESP. The kernel's forced command line carries
# `dtb=r8q.dtb`, and the EFI stub does NOT fall back to the firmware's device tree
# when that file is missing: it stops with "Failed to load device tree!", which
# Mu-Silicium reports as "Failed to find an operating system".
set -euo pipefail
USAGE="usage: deploy-esp.sh path/to/Image [path/to/sm8250-samsung-r8q.dtb]"
IMG="${1:?$USAGE}"
DTB="${2:-}"
[ -f "$IMG" ] || { echo "!! no such Image: $IMG"; exit 1; }
if [ -n "$DTB" ]; then
    [ "$(od -An -tx1 -N4 "$DTB" 2>/dev/null | tr -d ' \n')" = d00dfeed ] \
        || { echo "!! not a device tree blob: $DTB"; exit 1; }
fi
ESP="$(lsblk -o NAME,PARTLABEL -rn | awk '$2=="cache"{print "/dev/"$1}')"
[ -n "$ESP" ] || { echo "!! ESP (cache/R8QESP) not found — is the phone in mass storage?"; exit 1; }
MNT="$(mktemp -d)"; sudo mount "$ESP" "$MNT"
trap 'sudo umount "$MNT" 2>/dev/null; rmdir "$MNT" 2>/dev/null' EXIT
sudo mkdir -p "$MNT/EFI/BOOT"
sudo cp "$IMG" "$MNT/EFI/BOOT/BOOTAA64.EFI"
echo "[+] staged $IMG -> ESP:/EFI/BOOT/BOOTAA64.EFI"
if [ -n "$DTB" ]; then
    sudo cp "$DTB" "$MNT/r8q.dtb"
    echo "[+] staged $DTB -> ESP:/r8q.dtb"
fi
HAVE_DTB=0; [ -s "$MNT/r8q.dtb" ] && HAVE_DTB=1
sync
if [ "$HAVE_DTB" = 0 ]; then
    echo "!! ESP:/r8q.dtb is missing, so this kernel will NOT boot (cmdline has dtb=r8q.dtb)."
    echo "!! Re-run with the DTB as the second argument:"
    echo "!!   $USAGE"
    exit 1
fi
