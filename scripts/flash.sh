#!/usr/bin/env bash
# Flash the Mu-Silicium UEFI image to the BOOT partition.
# Phone must be in DOWNLOAD mode (power off; hold VolUp+VolDown; plug USB).
set -euo pipefail
IMG="${1:?usage: flash.sh path/to/Mu-r8q.img}"
heimdall detect
heimdall flash --BOOT "$IMG"   # heimdall reboots the phone
